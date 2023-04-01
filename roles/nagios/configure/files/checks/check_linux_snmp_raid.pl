#!/usr/bin/perl -w
#
# check_linux_snmp_raid Nagios plugin.  Checks a software RAID on Linux
#       and reports the status of the logical drives.
#
# Requires that Net::SNMP be installed on the monitored machine
#       and that the check_linux_raid.sh be added to snmpd.conf
#       as an extend:
#
#       extend .1.3.6.1.4.1.2021.52 mdstat /usr/local/bin/check_linux_raid.sh
#
# EXAMPLE
# Configuration in Nagios:
# define command {
#        command_name check_linux_snmp_raid
#        command_line $USER1$/check_linux_snmp_raid.pl -v 2c --debug_time -H $HOSTADDRESS$ -C $USER6$ -S "$SERVICESTATE$,$SERVICESTATETYPE$"
# }
# define service{
#        host_name                       list of target hosts
#        service_description             Linux RAID Status
#        check_command                   check_linux_snmp_raid
#        ...
# }
#

#--------------------------------------------------#
my $version = "0.1";
# Michal Halagiera, 2007.06.19
#--------------------------------------------------#

use strict;
use lib "/usr/lib/nagios/plugins";
use Net::SNMP qw(oid_lex_sort);
use utils qw($TIMEOUT %ERRORS);
use Getopt::Long;
use Time::HiRes qw(time);
Getopt::Long::Configure('bundling', 'no_ignore_case');

# variables
my(
$DEBUG,                 # print debug messages
$MAX_OUTPUTSTR,         # maximum number of characters in otput, default is 256
$session,
$error,
$line,
$foo,                   # represents an unused string
$host,
$port,
$community,
$username,
$authpasswd,
$authproto,
$privpasswd,
$privproto,
$timeout,
$alert,
$opt_H,
$opt_p,
$opt_C,
$opt_u,
$opt_a,
$opt_A,
$opt_x,
$opt_X,
$opt_t,
$opt_W,
$opt_snmpversion,
$opt_debug,
$opt_debugtime,
%debug_time,
);

sub help;
sub version;
sub print_usage;
sub print_output;
sub usage;

#--------------------------------------------------#
# need to manually define some things here

# for cases when you're not using utils.pm
# my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
# my $TIMEOUT=30;

$DEBUG = 0;     # to print debug messages, set this to 1
$MAX_OUTPUTSTR = 512;
#%LOGDRV_CODES = (
#       0 => ['offline', 'raid drive is offline'],
#       1 => ['degraded', 'raid array is degraded'],
#       2 => ['optimal', 'array funtioning properly'],
#       3 => ['initialize', 'currently initializing'],
#       4 => ['checkconsistency', 'raid array is being checked'],
#);

#%PHYDRV_CODES = (
#       1 => ['ready'],
#       3 => ['online'],
#       4 => ['failed'],
#       5 => ['rebuild'],
#       6 => ['hotspare'],
#       20 => ['nondisk'],
#);

# for snmpd with extend in snmpd.conf
my $exit_code_oid = ".1.3.6.1.4.1.2021.52.3.1.4.6.109.100.115.116.97.116";
my $output_oid = ".1.3.6.1.4.1.2021.52.4.1.2.6.109.100.115.116.97.116.1";

# for snmpd with exec in snmpd.conf
#my $exit_code_oid = ".1.3.6.1.4.1.2021.52.100.1";
#my $output_oid = ".1.3.6.1.4.1.2021.52.101.1";

#--------------------------------------------------#
# parse command line arguments

GetOptions (
        "h|help"                => \&help,
        "V|version"             => \&version,
        "H|hostname=s"          => \$opt_H,
        "p|port=s"              => \$opt_p,
        "C|community=s"         => \$opt_C,
        "u|username=s"          => \$opt_u,
        "a|authpassword=s"      => \$opt_a,
        "A|authproto=s"         => \$opt_A,
        "x|privpassword=s"      => \$opt_x,
        "X|privproto=s"         => \$opt_X,
        "t|timeout=s"           => \$opt_t,
        "v|snmp_version=s"      => \$opt_snmpversion,
        "W|alert=s"             => \$opt_W,
        "d|debug"               => \$opt_debug,
        "debug_time"            => \$opt_debugtime
);

$debug_time{plugin_start}=time() if $opt_debugtime;

# hostname
($opt_H) || usage("Hostname or IP address not specified\n");
$host = $1 if ($opt_H =~ m/^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|[a-zA-Z][-a-zA-Z0-9]*(\.[a-zA-Z][-a-zA-Z0-9]*)*)$/);
if (!($host)) {
        usage("Invalid hostname: $opt_H\n");
}

# choose correct SNMP version
if ($opt_snmpversion eq '3'){
        # username
        ($opt_u) || usage("SNMPv3 username not specified\n");
        $username = $opt_u;

        # authpassword
        ($opt_a) || usage("SNMPv3 authpassword not specified\n");
        $authpasswd = $opt_a;

        # authproto
        ($opt_A) || usage("SNMPv3 authproto not specified\n");
        $authproto = $opt_A;

        # privpassword
        ($opt_x) || usage("SNMPv3 privpassword not specified\n");
        $privpasswd = $opt_x;

        # privpassword
        ($opt_X) || usage("SNMPv3 privproto not specified\n");
        $privproto = $opt_X;
}
elsif ($opt_snmpversion eq '2c' || $opt_snmpversion eq '1') {
        # community string - defaults to "public"
        ($opt_C) || ($opt_C = "public");
        $community = $opt_C;
}
else {
        usage ("Incorrect SNMP version specified\n");
}

# port number - defaults to 161
($opt_p) || ($opt_p = 161);
($opt_p =~ m/^[0-9]+$/) || usage("Invalid port number: $opt_p\n");
$port = $opt_p;

# timeout - defaults to netsaint timeout
($opt_t) || ($opt_t = $TIMEOUT);
($opt_t =~ m/^[0-9]+$/) || usage("Invalid timeout value: $opt_t\n");
$timeout = $opt_t;

# alert - defaults to "crit"
($opt_W) || ($opt_W = "crit");
if ($opt_W =~ /warn/) {
        $alert = "WARNING";
} elsif ($opt_W =~ /crit/) {
        $alert = "CRITICAL";
} else {
        usage("Invalid alert: $opt_W\n");
        &print_usage;
        $alert = "UNKNOWN";
#       $nagios_status = "UNKNOWN";
}

$DEBUG=$opt_debug if defined($opt_debug) && $opt_debug;
if ($DEBUG) {
        print "hostname: $host >>$opt_H<<\n";
        print "port: $port >>$opt_p<<\n";
        print "version: $opt_snmpversion >>$opt_snmpversion<<\n";
        if ($opt_snmpversion eq '2c' || $opt_snmpversion eq '1') {
                print "community: $community >>$opt_C<<\n";
        }
        print "timeout: $timeout >>$opt_t<<\n";
        print "alert: $alert >>$opt_W<<\n";
}

#--------------------------------------------------#
# open the snmp connection and fetch the data
if ($DEBUG) {
        print "host = $host\n";
}

# set the timeout
$SIG{'ALRM'} = sub {
        if(defined($session)) {
                $session->close;
        }
        print_output("UNKNOWN","snmp query timed out");
        exit $ERRORS{"UNKNOWN"};
};
alarm($timeout);

# open the snmp connection
if ($opt_snmpversion eq '3') {
        ($session, $error) = Net::SNMP->session(
                -hostname      => $host,
                -version       => $opt_snmpversion,
                -port          => $port,
                -username      => $username,
                -authpassword  => $authpasswd,
                -authprotocol  => $authproto,
                -privpassword  => $privpasswd,
                -privprotocol  => $privproto,
                -timeout       => $timeout
        );
}
else {
        ($session, $error) = Net::SNMP->session(
                -hostname      => $host,
                -version       => $opt_snmpversion,
                -port          => $port,
                -community     => $community,
                -timeout       => $timeout
        );
}

if (!defined($session)) {
        if ($DEBUG) {
                print("snmp connection error: $error.\n");
        }
        print_output("UNKNOWN","no data received");
        exit $ERRORS{"UNKNOWN"};
}

# fetch snmp data
$error="";
$debug_time{snmpretrieve_oids}=time() if $opt_debugtime;
my $snmp_result=$session->get_request(-Varbindlist => [ $exit_code_oid, $output_oid ]);
$debug_time{snmpretrieve_oids}=time()-$debug_time{snmpretrieve_oids} if $opt_debugtime;
$error.="could not retrieve snmp data OIDs" if !$snmp_result && !$error;

$debug_time{snmpgettable_exit_code}=time() if $opt_debugtime;
#my $exit_code_data_in = $session->get_table(-baseoid => $exit_code_oid) if !$error;
my $exit_code_data_in = $snmp_result->{$exit_code_oid} if !$error;
$debug_time{snmpgettable_exit_code}=time()-$debug_time{snmpgettable_exit_code} if $opt_debugtime;
$error.= "could not retrieve snmp table $exit_code_oid" if $exit_code_data_in eq '' && !$error;

$debug_time{snmpgettable_output}=time() if $opt_debugtime;
#my $output_data_in = $session->get_table(-baseoid => $output_oid) if !$error;
my $output_data_in = $snmp_result->{$output_oid} if !$error;
$debug_time{snmpgettable_output}=time()-$debug_time{snmpgettable_output} if $opt_debugtime;
$error.= "could not retrieve snmp table $output_oid" if $output_data_in eq '' && !$error;

if ($error) {
        if ($DEBUG) {
                printf("snmp error: %s\n", $session->error());
        }
        $session->close;
        print_output("UNKNOWN",$error);
        exit $ERRORS{'UNKNOWN'};
}

# close the snmp connection
$session->close;

#--------------------------------------------------#
# parse the data and determine status

$debug_time{plugin_finish}=time() if $opt_debugtime;
$debug_time{plugin_totaltime}=$debug_time{plugin_finish}-$debug_time{plugin_start} if $opt_debugtime;

my $output = $output_data_in;
my $exit_code = $exit_code_data_in;

print_output("",$output);
exit $exit_code;

#--------------------------------------------------#
# version flag function
sub version {
        print "$0 version $version\n";
        exit $ERRORS{'UNKNOWN'};
}

#--------------------------------------------------#
# display help information
sub help {
        print "Checks logical and physical drive status of Linux software RAID.\n";
        print "\n";
        print_usage();
        print "\n";
        print "Options:\n";
        print "  -h, --help\n";
        print "    Display help\n";
        print "  -V, --version\n";
        print "    Display version\n";
        print "  -H, --hostname <host>\n";
        print "    Hostname or IP address of target to check\n";
        print "  -p, --port <port>\n";
        print "    SNMP port (defaults to 161)\n";
        print "  -C, --community <community>\n";
        print "    SNMP community string (defaults to \"public\")\n";
        print "  -a, --authpassword <password>\n";
        print "    SNMPv3 authpassword\n";
        print "  -A, --authproto <proto>\n";
        print "    SNMPv3 authprotocol\n";
        print "  -x, --privpassword <password>\n";
        print "    SNMPv3 privpassword\n";
        print "  -X, --privproto <proto>\n";
        print "    SNMPv3 privprotocol\n";
        print "  -s, --snmp_version 1 | 2c | 3";
        print "    Version of SNMP protocol to use - default is 2c\n";
        print "  -t, --timeout <timeout>\n";
        print "    Seconds before timing out (defaults to Netsaint timeout value)\n";
        print "  -W, --alert <alert level>\n";
        print "    Alert status to use if an error condition is found\n";
        print "    Accepted values are: \"crit\" and \"warn\" (defaults to crit)\n";
        print "  -d, --debug\n";
        print "    Increases verbosity level\n";
        print "  --debug_time\n";
        print "    Prints execution time infrmation\n";
        print "\n";
        exit $ERRORS{'UNKNOWN'};
}

sub usage {
        print $_."\n" foreach @_;
        print_usage();
        exit $ERRORS{'UNKNOWN'};
}

#--------------------------------------------------#
# display usage information
sub print_usage {
        print "Usage:\n";
        print "$0 -H <host> -v <version> [-p <port>] [[-C <community>] | [-a <password>] [-A <proto>] [-x <password>] [-X <proto>]] [-t <timeout>] [-a <alert level>] [-d] [--debug_time]\n";
        print "$0 --help\n";
        print "$0 --version\n";
}

sub print_output {
   my ($out_status,$out_str)=@_;

   if ($out_status) {
      print "$out_status - ";
   }
   print "$out_str" if $out_str;
   print "\n";
   if ($opt_debugtime) {
      print " time_".$_ ."=". $debug_time{$_} foreach keys %debug_time;
   }
}
#!/usr/bin/perl -w
#
# check_linux_snmp_raid Nagios plugin.  Checks a software RAID on Linux
#       and reports the status of the logical drives.
#
# Requires that Net::SNMP be installed on the monitored machine
#       and that the check_linux_raid.sh be added to snmpd.conf
#       as an extend:
#
#       extend .1.3.6.1.4.1.2021.52 mdstat /usr/local/bin/check_linux_raid.sh
#
# EXAMPLE
# Configuration in Nagios:
# define command {
#        command_name check_linux_snmp_raid
#        command_line $USER1$/check_linux_snmp_raid.pl -v 2c --debug_time -H $HOSTADDRESS$ -C $USER6$ -S "$SERVICESTATE$,$SERVICESTATETYPE$"
# }
# define service{
#        host_name                       list of target hosts
#        service_description             Linux RAID Status
#        check_command                   check_linux_snmp_raid
#        ...
# }
#

#--------------------------------------------------#
my $version = "0.1";
# Michal Halagiera, 2007.06.19
#--------------------------------------------------#

use strict;
use lib "/usr/lib/nagios/plugins";
use Net::SNMP qw(oid_lex_sort);
use utils qw($TIMEOUT %ERRORS);
use Getopt::Long;
use Time::HiRes qw(time);
Getopt::Long::Configure('bundling', 'no_ignore_case');

# variables
my(
$DEBUG,                 # print debug messages
$MAX_OUTPUTSTR,         # maximum number of characters in otput, default is 256
$session,
$error,
$line,
$foo,                   # represents an unused string
$host,
$port,
$community,
$username,
$authpasswd,
$authproto,
$privpasswd,
$privproto,
$timeout,
$alert,
$opt_H,
$opt_p,
$opt_C,
$opt_u,
$opt_a,
$opt_A,
$opt_x,
$opt_X,
$opt_t,
$opt_W,
$opt_snmpversion,
$opt_debug,
$opt_debugtime,
%debug_time,
);

sub help;
sub version;
sub print_usage;
sub print_output;
sub usage;

#--------------------------------------------------#
# need to manually define some things here

# for cases when you're not using utils.pm
# my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
# my $TIMEOUT=30;

$DEBUG = 0;     # to print debug messages, set this to 1
$MAX_OUTPUTSTR = 512;
#%LOGDRV_CODES = (
#       0 => ['offline', 'raid drive is offline'],
#       1 => ['degraded', 'raid array is degraded'],
#       2 => ['optimal', 'array funtioning properly'],
#       3 => ['initialize', 'currently initializing'],
#       4 => ['checkconsistency', 'raid array is being checked'],
#);

#%PHYDRV_CODES = (
#       1 => ['ready'],
#       3 => ['online'],
#       4 => ['failed'],
#       5 => ['rebuild'],
#       6 => ['hotspare'],
#       20 => ['nondisk'],
#);

# for snmpd with extend in snmpd.conf
my $exit_code_oid = ".1.3.6.1.4.1.2021.52.3.1.4.6.109.100.115.116.97.116";
my $output_oid = ".1.3.6.1.4.1.2021.52.4.1.2.6.109.100.115.116.97.116.1";

# for snmpd with exec in snmpd.conf
#my $exit_code_oid = ".1.3.6.1.4.1.2021.52.100.1";
#my $output_oid = ".1.3.6.1.4.1.2021.52.101.1";

#--------------------------------------------------#
# parse command line arguments

GetOptions (
        "h|help"                => \&help,
        "V|version"             => \&version,
        "H|hostname=s"          => \$opt_H,
        "p|port=s"              => \$opt_p,
        "C|community=s"         => \$opt_C,
        "u|username=s"          => \$opt_u,
        "a|authpassword=s"      => \$opt_a,
        "A|authproto=s"         => \$opt_A,
        "x|privpassword=s"      => \$opt_x,
        "X|privproto=s"         => \$opt_X,
        "t|timeout=s"           => \$opt_t,
        "v|snmp_version=s"      => \$opt_snmpversion,
        "W|alert=s"             => \$opt_W,
        "d|debug"               => \$opt_debug,
        "debug_time"            => \$opt_debugtime
);

$debug_time{plugin_start}=time() if $opt_debugtime;

# hostname
($opt_H) || usage("Hostname or IP address not specified\n");
$host = $1 if ($opt_H =~ m/^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|[a-zA-Z][-a-zA-Z0-9]*(\.[a-zA-Z][-a-zA-Z0-9]*)*)$/);
if (!($host)) {
        usage("Invalid hostname: $opt_H\n");
}

# choose correct SNMP version
if ($opt_snmpversion eq '3'){
        # username
        ($opt_u) || usage("SNMPv3 username not specified\n");
        $username = $opt_u;

        # authpassword
        ($opt_a) || usage("SNMPv3 authpassword not specified\n");
        $authpasswd = $opt_a;

        # authproto
        ($opt_A) || usage("SNMPv3 authproto not specified\n");
        $authproto = $opt_A;

        # privpassword
        ($opt_x) || usage("SNMPv3 privpassword not specified\n");
        $privpasswd = $opt_x;

        # privpassword
        ($opt_X) || usage("SNMPv3 privproto not specified\n");
        $privproto = $opt_X;
}
elsif ($opt_snmpversion eq '2c' || $opt_snmpversion eq '1') {
        # community string - defaults to "public"
        ($opt_C) || ($opt_C = "public");
        $community = $opt_C;
}
else {
        usage ("Incorrect SNMP version specified\n");
}

# port number - defaults to 161
($opt_p) || ($opt_p = 161);
($opt_p =~ m/^[0-9]+$/) || usage("Invalid port number: $opt_p\n");
$port = $opt_p;

# timeout - defaults to netsaint timeout
($opt_t) || ($opt_t = $TIMEOUT);
($opt_t =~ m/^[0-9]+$/) || usage("Invalid timeout value: $opt_t\n");
$timeout = $opt_t;

# alert - defaults to "crit"
($opt_W) || ($opt_W = "crit");
if ($opt_W =~ /warn/) {
        $alert = "WARNING";
} elsif ($opt_W =~ /crit/) {
        $alert = "CRITICAL";
} else {
        usage("Invalid alert: $opt_W\n");
        &print_usage;
        $alert = "UNKNOWN";
#       $nagios_status = "UNKNOWN";
}

$DEBUG=$opt_debug if defined($opt_debug) && $opt_debug;
if ($DEBUG) {
        print "hostname: $host >>$opt_H<<\n";
        print "port: $port >>$opt_p<<\n";
        print "version: $opt_snmpversion >>$opt_snmpversion<<\n";
        if ($opt_snmpversion eq '2c' || $opt_snmpversion eq '1') {
                print "community: $community >>$opt_C<<\n";
        }
        print "timeout: $timeout >>$opt_t<<\n";
        print "alert: $alert >>$opt_W<<\n";
}

#--------------------------------------------------#
# open the snmp connection and fetch the data
if ($DEBUG) {
        print "host = $host\n";
}

# set the timeout
$SIG{'ALRM'} = sub {
        if(defined($session)) {
                $session->close;
        }
        print_output("UNKNOWN","snmp query timed out");
        exit $ERRORS{"UNKNOWN"};
};
alarm($timeout);

# open the snmp connection
if ($opt_snmpversion eq '3') {
        ($session, $error) = Net::SNMP->session(
                -hostname      => $host,
                -version       => $opt_snmpversion,
                -port          => $port,
                -username      => $username,
                -authpassword  => $authpasswd,
                -authprotocol  => $authproto,
                -privpassword  => $privpasswd,
                -privprotocol  => $privproto,
                -timeout       => $timeout
        );
}
else {
        ($session, $error) = Net::SNMP->session(
                -hostname      => $host,
                -version       => $opt_snmpversion,
                -port          => $port,
                -community     => $community,
                -timeout       => $timeout
        );
}

if (!defined($session)) {
        if ($DEBUG) {
                print("snmp connection error: $error.\n");
        }
        print_output("UNKNOWN","no data received");
        exit $ERRORS{"UNKNOWN"};
}

# fetch snmp data
$error="";
$debug_time{snmpretrieve_oids}=time() if $opt_debugtime;
my $snmp_result=$session->get_request(-Varbindlist => [ $exit_code_oid, $output_oid ]);
$debug_time{snmpretrieve_oids}=time()-$debug_time{snmpretrieve_oids} if $opt_debugtime;
$error.="could not retrieve snmp data OIDs" if !$snmp_result && !$error;

$debug_time{snmpgettable_exit_code}=time() if $opt_debugtime;
#my $exit_code_data_in = $session->get_table(-baseoid => $exit_code_oid) if !$error;
my $exit_code_data_in = $snmp_result->{$exit_code_oid} if !$error;
$debug_time{snmpgettable_exit_code}=time()-$debug_time{snmpgettable_exit_code} if $opt_debugtime;
$error.= "could not retrieve snmp table $exit_code_oid" if $exit_code_data_in eq '' && !$error;

$debug_time{snmpgettable_output}=time() if $opt_debugtime;
#my $output_data_in = $session->get_table(-baseoid => $output_oid) if !$error;
my $output_data_in = $snmp_result->{$output_oid} if !$error;
$debug_time{snmpgettable_output}=time()-$debug_time{snmpgettable_output} if $opt_debugtime;
$error.= "could not retrieve snmp table $output_oid" if $output_data_in eq '' && !$error;

if ($error) {
        if ($DEBUG) {
                printf("snmp error: %s\n", $session->error());
        }
        $session->close;
        print_output("UNKNOWN",$error);
        exit $ERRORS{'UNKNOWN'};
}

# close the snmp connection
$session->close;

#--------------------------------------------------#
# parse the data and determine status

$debug_time{plugin_finish}=time() if $opt_debugtime;
$debug_time{plugin_totaltime}=$debug_time{plugin_finish}-$debug_time{plugin_start} if $opt_debugtime;

my $output = $output_data_in;
my $exit_code = $exit_code_data_in;

print_output("",$output);
exit $exit_code;

#--------------------------------------------------#
# version flag function
sub version {
        print "$0 version $version\n";
        exit $ERRORS{'UNKNOWN'};
}

#--------------------------------------------------#
# display help information
sub help {
        print "Checks logical and physical drive status of Linux software RAID.\n";
        print "\n";
        print_usage();
        print "\n";
        print "Options:\n";
        print "  -h, --help\n";
        print "    Display help\n";
        print "  -V, --version\n";
        print "    Display version\n";
        print "  -H, --hostname <host>\n";
        print "    Hostname or IP address of target to check\n";
        print "  -p, --port <port>\n";
        print "    SNMP port (defaults to 161)\n";
        print "  -C, --community <community>\n";
        print "    SNMP community string (defaults to \"public\")\n";
        print "  -a, --authpassword <password>\n";
        print "    SNMPv3 authpassword\n";
        print "  -A, --authproto <proto>\n";
        print "    SNMPv3 authprotocol\n";
        print "  -x, --privpassword <password>\n";
        print "    SNMPv3 privpassword\n";
        print "  -X, --privproto <proto>\n";
        print "    SNMPv3 privprotocol\n";
        print "  -s, --snmp_version 1 | 2c | 3";
        print "    Version of SNMP protocol to use - default is 2c\n";
        print "  -t, --timeout <timeout>\n";
        print "    Seconds before timing out (defaults to Netsaint timeout value)\n";
        print "  -W, --alert <alert level>\n";
        print "    Alert status to use if an error condition is found\n";
        print "    Accepted values are: \"crit\" and \"warn\" (defaults to crit)\n";
        print "  -d, --debug\n";
        print "    Increases verbosity level\n";
        print "  --debug_time\n";
        print "    Prints execution time infrmation\n";
        print "\n";
        exit $ERRORS{'UNKNOWN'};
}

sub usage {
        print $_."\n" foreach @_;
        print_usage();
        exit $ERRORS{'UNKNOWN'};
}

#--------------------------------------------------#
# display usage information
sub print_usage {
        print "Usage:\n";
        print "$0 -H <host> -v <version> [-p <port>] [[-C <community>] | [-a <password>] [-A <proto>] [-x <password>] [-X <proto>]] [-t <timeout>] [-a <alert level>] [-d] [--debug_time]\n";
        print "$0 --help\n";
        print "$0 --version\n";
}

sub print_output {
   my ($out_status,$out_str)=@_;

   if ($out_status) {
      print "$out_status - ";
   }
   print "$out_str" if $out_str;
   print "\n";
   if ($opt_debugtime) {
      print " time_".$_ ."=". $debug_time{$_} foreach keys %debug_time;
   }
}
