#!/usr/bin/perl

# nagios: -epn
# --
# check_hp_imc - Check HPE iMC status
# Copyright (C) 2017 Giorgio Maggiolo, http://www.maggiolo.net/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --
# 

use strict;

use common::sense;
use LWP::UserAgent;
use Data::Dumper;
use HTTP::Request;
use XML::LibXML;
use Getopt::Long;

GetOptions (
			"server=s" => \my $server,
			"port=i" => \my $port,
			"username=s" => \my $username,
			"password=s" => \my $password,
			"operation=s" => \my $operation,
			"realm=s" => \my $realm,
			"h|help" => sub { exec perldoc => -F => $0 or die "Cannot execute perldoc: $!\n"; },
			"warning=i" => \my $warning,
			"critical=i" => \my $critical,
			"performance" => \my $performance,
) or Error("$0: Error in command line arguments\n");

sub Error {
    print "$0: " . $_[0] . "\n";
    exit 2;
}

sub get_xml_text {
	my $rest_call_local = $_[0];
	my $browser = LWP::UserAgent->new();
	my $req = HTTP::Request->new();
	$browser->credentials("$server:$port",$realm,$username,$password);
	$req->uri("http://$server:$port/imcrs/$rest_call_local");
	$req->method('GET');
	$req->header('Content_Type' => 'application/xml');
	my $response = $browser->request($req);
	die "Error: ", $response->status_line, "\n", Dumper($response->headers), "\n\n\n", "Is the REALM correct: ",$response->header("WWW-Authenticate"), "== ", $realm unless $response->is_success;
	return $response;
}

sub license_check {
	Error('Option --warning required') unless $warning;
	Error('Option --critical required') unless $critical;
	my $function = "plat/licenseInfo/allLicenseMsg";
	my $xml_response = get_xml_text($function);
	my $dom = XML::LibXML->load_xml(string => $xml_response->content);
	my $license_info_element = $dom->getElementsByTagName("list")->get_node(1)->getElementsByTagName("licenseInfo")->get_node(1);
	my $max_count = $license_info_element->getElementsByTagName("maxCount")->string_value();
	my $lic_used_count = $license_info_element->getElementsByTagName("licUsedCount")->string_value();
	my $free_licences = $max_count - $lic_used_count;
	if ($free_licences < $critical){
		print "CRITICAL: there are $free_licences free licences";
		if ($performance){
			print " | 'free_licences'=$free_licences;$warning;$critical\n";
		} else {
			print "\n";
		}
		exit(2);
	} elsif ($free_licences < $warning) {
		print "WARNING: there are $free_licences free licences";
		if ($performance){
			print " | 'free_licences'=$free_licences;$warning;$critical\n";
		} else {
			print "\n";
		}
		exit(1);
	} else {
		print "OK: there are $free_licences free licences";
		if ($performance){
			print " | 'free_licences'=$free_licences;$warning;$critical\n";
		} else {
			print "\n";
		}
		exit(0);
	}
}

sub get_current_alarm {
	my $function = "fault/alarm?operatorName=$username&alarmLevel=$_[0]&recStatus=0&ackStatus=0&size=200&desc=false";
	my $xml_response = get_xml_text($function);
	my $dom = XML::LibXML->load_xml(string => $xml_response->content);
	my $list_element = $dom->getElementsByTagName("list")->get_node(1);
	return $list_element->getElementsByTagName("alarm");
}

sub get_down_devices {
	my $error_level="1";
	my @error_devices = get_current_alarm($error_level);
	if (@error_devices){
		my $return_string;
		foreach my $node (@error_devices){
			if ($node->getElementsByTagName("alarmDesc")->string_value() =~ /Device "(.*)" does not respond/){
				my $device_name = $node->getElementsByTagName("deviceName")->string_value();
				$device_name =~ /([^\d]{4,}[\d]{3})(\s)?(-)?/;
				$device_name = $1;
				if ($return_string eq ""){
					$return_string = $device_name;
				} else {
					$return_string .= ", $device_name";
				}
			}
		}
		print "CRITICAL: there are offline devices: $return_string\n";
		exit(2);
	} else{
		print "OK - All devices are fine\n";
		exit(0);
	}
}

sub get_backup_error {
	my $error_level="4";
	my @error_devices = get_current_alarm($error_level);
	my %return_device_hash = {};
	if (@error_devices){
		my $return_string;
		foreach my $node (@error_devices){
			if ($node->getElementsByTagName("alarmDesc")->string_value() =~ /During backup, found that (\w*) configuration file "(.*) baseline/){
				my $what_file = $1;
				my $device_name = $node->getElementsByTagName("deviceName")->string_value();
				$device_name =~ /([^\d]{4,}[\d]{3})(\s)?(-)?/;
				$device_name = $1;
				if ($return_device_hash{$device_name} eq ""){
					$return_device_hash{$device_name} = $what_file;
				} else {
					$return_device_hash{$device_name} .= ", $what_file";
				}
			} 
		}
		for my $key (keys %return_device_hash){
			if ($return_device_hash{$key} =~ /(.*), (.*)/){
				if ($return_string eq ""){
					$return_string = "$key (RUN & START)";
				} else {
					$return_string .= ", $key (RUN & START)";
				}
			} elsif ($return_device_hash{$key} =~ /running/){
				if ($return_string eq ""){
					$return_string = "$key (RUN)";
				} else {
					$return_string .= ", $key (RUN)";
				}
			} elsif ($return_device_hash{$key} =~ /startup/){
				if ($return_string eq ""){
					$return_string = "$key (START)";
				} else {
					$return_string .= ", $key (START)";
				}
			}
		}
		print "WARNING: there are different backups: $return_string\n";
		exit(1);
	} else{
		print "OK - All devices backups are fine\n";
		exit(0);
	}
}


Error('Option --server required') unless $server;
Error('Option --username required') unless $username;
Error('Option --password required') unless $password;
$realm = "iMC RESTful Web Services" unless $realm;
$port = "8080" unless $port;

if($operation eq "license_check"){
	license_check();
} elsif ($operation eq "get_down_devices"){
	get_down_devices();
} elsif ($operation eq "get_backup_error"){
	get_backup_error();
} else {
	print "UNKNOWN: Operation parameter not recognized\n";
	exit(3);
}


__END__

=head1 NAME

check_hp_imc - Check HPE iMC environment

=head1 SYNOPSIS

check_hp_imc.pl --server SERVER_IP [--port PORT] --username USERNAME --password PASSWORD --operation OPERATION [-h|--help] 

=head1 DESCRIPTION

Connects to a HPE iMC and performe some checks on it.

=head1 OPTIONS

=over 4

=item --server SERVER

FQDN or IP Address of the HPE iMC

=item --port PORT

Optional: Port used to connect to the HPE iMC eAPIs

=item -u | --username USERNAME

The Username used to connect to the HPE iMC eAPIs

=item -p | --password PASSWORD

The Password used to connect to the HPE iMC eAPIs

=item --warning WARNING

The Warning threshold for tests that expect a threshold

=item --critical CRITICAL

The Critical threshold for tests that expect a threshold

=item --operation OPERATION

List of the possible operations that the script checks against the SERVER iMC. Where written "W/C" means that WARNING and CRITICAL values are needed.
Possible values:

	- license_check (W/C): verify how many free licenses are left and raise a WARNING/CRITICAL alarm if the thresholds are reached

	- get_down_devices: verify that there are no down devices and, in case, raise a CRITICAL alarm and write down the list of the devices 

	- get_backup_error: verify whether any device has a backup that is different from the baseline and raise a WARNING alarm in case

=item --performance

Flag for performance data output

=item -h | --help

Tqo see this Documentation

=back

=head1 EXIT CODE

3 on Unknown Errors 

2 if Critical Threshold has been reached

1 if Warning Threshold has been reached

0 if everything is ok

=head1 AUTHORS

 Giorgio Maggiolo <giorgio at maggiolo dot net>
