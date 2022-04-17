package Plugins::Build::Cmds::Build;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);
use File::Path qw(make_path remove_tree);

use InVivo qw(kexists kdelete);
use PSI::Console qw(print_table print_line print_structure);
use PSI::Parse::File qw(write_files);
use PSI::Tag qw(get_tag);
use PSI::RunCmds qw(run_system run_open);
use Tree::Slice qw(slice_tree);

use Plugins::Build::Filter::DNS qw(generate_dns);
use Plugins::Build::Filter::Machines qw(add_machines);
use Plugins::Build::Filter::Secrets qw(add_secrets);
use Plugins::Build::Filter::Services qw(add_services);
use Plugins::Build::Filter::Roles qw(apply_role);

use Plugins::Build::Lib::Image qw(build_image);
use Plugins::Build::Lib::Archive qw(build_archive);

use Process::Manager qw(task_manager);
use IO::Templates::Update qw(update_templates);
use IO::Templates::Parse qw(get_template_files get_template_dirs);
use IO::Templates::Write qw(write_templates);
use IO::Config::Write qw(write_config);
use IO::Config::Check qw(file_exists);

our @EXPORT_OK = qw(import_build);

my $generated_dns_config;    # workaround for DNS config generation

#################################################

sub _get_core_count() {

    my ( $core_count, @o ) = run_open '/usr/bin/nproc';
    return $core_count;
}

sub _check_empty_leaves($tree) {

    # check for empty leaves
    my $cond = sub ($b) {

        return if ref $b->[0];

        if ( !defined( $b->[0] ) ) {
            my $path = join( '->', $b->[1]->@* );
            die "ERROR: leaf $path contains undefined value";
        }
        return;
    };
    slice_tree( $tree, $cond );
    return;
}

sub _save_dns_config ( $dns_config, $path ) {

    print_table( 'Saving DNS Config', $path, ': ' );

    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Terse  = 1;

    write_files(
        "$path/",
        [
            {
                LOCATION => 'dns.cfgen',
                CONTENT  => [ Dumper $dns_config ],
                CHMOD    => '700',
            }
        ],
        [],
        0
    );

    say 'OK';
    return;
}

# this function generates a complete set of configuration for each machine.
sub _assemble_config ( $query, $arg_cluster, $arg_machine ) {

    # create base structure
    my $assembled_config = add_machines( $query->('cluster'), $query->('container'), $query->('images'), $query->('accounts') );
    $generated_dns_config = generate_dns($assembled_config);

    # delete everything from the tree but args, if set
    if ($arg_cluster) {
        print_line "Only Building network $arg_cluster";
        die "ERROR: network $arg_cluster does not exist" unless ( exists( $assembled_config->{$arg_cluster} ) );

        for my $c ( keys $assembled_config->%* ) {
            delete $assembled_config->{$c} unless $c eq $arg_cluster;
        }
        if ($arg_machine) {
            print_line "Only Building machine $arg_machine";
            die "ERROR: network $arg_cluster does not exist" unless ( kexists( $assembled_config, $arg_cluster, $arg_machine ) );

            for my $m ( keys $assembled_config->{$arg_cluster}->%* ) {
                kdelete( $assembled_config, $arg_cluster, $m ) unless $m eq $arg_machine;
            }
        }
    }

    # add the rest
    foreach my $cluster_name ( keys( $assembled_config->%* ) ) {

        # yes, clusters, not assembled_config, as we want to add stuff thats not yet in assembled_config,
        # but only for entries of assembled_config
        my $cluster = $assembled_config->{$cluster_name};

        foreach my $machine_name ( keys $cluster->%* ) {

            # the container iteration above created entries to assembled_config for each machine
            my $assembled_machine = $cluster->{$machine_name};

            $assembled_machine->{paths}     = $query->('paths');
            $assembled_machine->{images}    = $query->('images');
            $assembled_machine->{bootstrap} = $query->('bootstrap');
            $assembled_machine->{hostos}    = $query->('hostos');
            $assembled_machine->{service}   = dclone add_services( $assembled_machine->{machine}->{self}, $query->('services') );
        }
    }

    # this inserts the secrets, has to be done before templates get filled
    add_secrets( $assembled_config, $query->('secrets') );

    #print_structure $assembled_config;
    # this substitutes most variables.
    update_templates($assembled_config);

    # now that the config is complete, remove config from machines that dont suit their role
    # and add genesis itself
    apply_role( $assembled_config, $query->('roles'), $query->('genesis') );

    _check_empty_leaves($assembled_config);

    return $assembled_config;
}

sub _write_to_disk($p) {

    my $path            = $p->{cf_base};
    my $config          = $p->{config};
    my $genesis         = delete $config->{genesis};
    my $bootstrap       = delete $config->{bootstrap};
    my $files_path      = "$path/files";
    my $mount_path      = "$path/mnt";
    my $cf_path         = join( '/', $files_path, 'genesis', 'Config' );
    my @bootstrap_files = get_template_files($bootstrap);
    my @bootstrap_dirs  = get_template_dirs($bootstrap);
    my $test_failed     = 0;
    my $test_genesis    = sub ($p) {
        say "FAILED: $p->{child_ec} ( $p->{msg})";
        $test_failed = 1;
        return;
    };

    build_archive(
        {
            files        => \@bootstrap_files,
            dirs         => \@bootstrap_dirs,
            archive_name => join( '_', 'bootstrap', $p->{cluster_name}, $p->{machine_name}, '_', $p->{tag} ),
            archive_path => $p->{image_path},
        }
    );

    ######################
    print_table( 'Saving Genesis', $files_path, ': ' );
    {
        local ( $?, $! );
        remove_tree( $path, { keep_root => 1 } ) if ( file_exists $files_path );
        make_path($files_path);
        make_path($cf_path);
    }
    write_templates( $files_path, $genesis, 0 );
    say 'OK';

    #######################

    print_table( 'Saving Config', $cf_path, ': ' );
    write_config( $cf_path, $config, [ keys $genesis->{genesis}->{Plugins}->%* ] );
    say 'OK';

    {
        local ( $?, $! );
        make_path($mount_path);
    }

    # maybe make this its own command, and then have macros that you actually execute
    # a test command would be nice, that walks through all latest images, mounts and executes them with system echo 'test success' to see if they load
    # flush config out to disk
    # folder needs to be gotten from config, and appended with genesis, cluster_name, machine_name
    my $to_name = join( '_', 'genesis', $p->{cluster_name}, $p->{machine_name}, '_', $p->{tag} );

    build_image(
        {
            to_file  => $to_name,
            to_dir   => $p->{image_path},
            from_dir => $files_path,
            tmp_dir  => $path,
            mount    => $mount_path
        }
    );

    print_table( 'Testing', $to_name, ': ' );

    my $image_fp = join( '/', $path, $to_name );
    run_system( $test_genesis, "mount $image_fp $mount_path && cd $mount_path/genesis && export GENESIS_TEST=1 && ./genesis.pl system true > /dev/null 2>&1" );
    run_system( sub (@) { }, "umount -lf $mount_path" );    # may emit errors nobody cares for
    say 'OK' unless $test_failed;
    return;
}

sub _build ( $query, @args ) {

    # read command line arguments
    my ( $arg_cluster, $arg_machine );
    ( $arg_cluster, $arg_machine ) = split( /\//, $args[0] ) if ( $args[0] );

    my $tag              = get_tag;
    my $assembled_config = _assemble_config( $query, $arg_cluster, $arg_machine );
    my $paths            = $query->('paths');
    my $image_path       = $paths->{data}->{IMAGES};

    die 'ERROR: no image path found' unless $image_path;

    _save_dns_config( $generated_dns_config, $paths->{data}->{LOCAL_DNS_CONFIG} );

    my $workers = {};

    foreach my $cluster_name ( keys $assembled_config->%* ) {

        foreach my $machine_name ( keys $assembled_config->{$cluster_name}->%* ) {

            my $machine = $assembled_config->{$cluster_name}->{$machine_name};

            die 'ERROR: cf_path not found' unless ( kexists( $machine, 'paths', 'data', 'LOCAL_GENESIS_CONFIG' ) );

            # we need this outside of the loop
            my $local_genesis_config = $machine->{paths}->{data}->{LOCAL_GENESIS_CONFIG};
            my $base_path            = join( '/', $local_genesis_config, $cluster_name, $machine_name );

            $workers->{"$cluster_name/$machine_name"} = {
                TASK => sub($data) {
                    # Forks::Super does not clear this, so invoking anything that checks that will break
                    local $? = 0;
                    local $! = 0;
                    return _write_to_disk($data);
                },
                DATA => {
                    cf_base      => $base_path,
                    config       => $machine,
                    cluster_name => $cluster_name,
                    machine_name => $machine_name,
                    tag          => $tag,
                    image_path   => $image_path
                },
            };
        }
    }

    my $max_jobs = _get_core_count() * 2;
    task_manager( 0, $workers, $max_jobs );

    return;
}

###########################################
# frontend
#
sub import_build () {

    my $struct = {
        build => {
            CMD  => \&_build,
            DESC => 'builds genesis',
            HELP => ['usage: build [[cluster]/machine]'],
            DATA => {
                images    => 'state images',
                accounts  => 'state accounts',
                cluster   => 'state cluster',
                container => 'state container',
                secrets   => 'state secrets',
                services  => 'state services',
                roles     => 'state roles',
                paths     => 'state paths',
                genesis   => 'state genesis',
                bootstrap => 'state bootstrap',
                hostos    => 'state hostos',
            }
        }
    };

    return $struct;
}
1;
