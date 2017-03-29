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
			"device=s" => \my $device_name,
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

sub get_realtime_error {
	my $function = "fault/faultRealTime?operatorName=$username";
	my $xml_response = get_xml_text($function);
	my $dom = XML::LibXML->load_xml(string => $xml_response->content);
	my $list_element = $dom->getElementsByTagName("list")->get_node(1);
	if ($list_element->getElementsByTagName("count")->string_value() > 0){
		return $list_element->getElementsByTagName("faultRealTime")->get_node(1)->getElementsByTagName("faultRealTimeList");
		
	} else{
		return;
	}
}

sub get_down_devices {
	my @error_devices = get_realtime_error();
	if (@error_devices){
		my $return_string;
		foreach my $node (@error_devices){
			if ($node->getElementsByTagName("severity")->string_value() == "1" && $node->getElementsByTagName("userAckType")->string_value() == "0" && $node->getElementsByTagName("faultDesc")->string_value() =~ /Device "(.*)" does not respond/){
				if ($return_string eq ""){
					$return_string = $1;
				} else {
					$return_string .= ", $1";
				}
			} 
			print "CRITICAL: there are offline devices: $return_string\n";
			exit(2);
		}
	} else{
		print "OK - All devices are fine\n";
		exit(0);
	}
}


Error('Option --server required') unless $server;
Error('Option --username required') unless $username;
Error('Option --password required') unless $password;

$realm = "iMC RESTful Web Services" unless $realm;
$port = "8080" unless $port;

my $rest_call;

if($operation eq "license_check"){
	license_check();
} elsif ($operation eq "get_down_devices"){
	get_down_devices();
} else {
	print "UNKNOWN - Operation parameter not recognized\n";
	exit(3);
}


__END__

=head1 NAME

check_hp_imc - Check HPE iMC environment

=head1 SYNOPSIS

check_hp_imc.pl --server SERVER_IP --username USERNAME --password PASSWORD \
		[--port PORT] --operation OPERATION [--device DEVICE_NAME] [-h|--help] 

=head1 DESCRIPTION

Connects to a HPE iMC and performe some operations with it. \
It can be used to retrieve the managed devices status, for example

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

=item --size-warning PERCENT_WARNING

The Warning threshold for data space usage.

=item --size-critical PERCENT_CRITICAL

The Critical threshold for data space usage.

=item --inode-warning PERCENT_WARNING

The Warning threshold for inodes (files). Defaults to 65% if not given.

=item --inode-critical PERCENT_CRITICAL

The Critical threshold for inodes (files). Defaults to 85% if not given.

=item --snap-warning PERCENT_WARNING

The Warning threshold for snapshot space usage. Defaults to 75%.

=item --snap-critical PERCENT_CRITICAL

The Critical threshold for snapshot space usage. Defaults to 90%.

=item -V | --volume VOLUME

Optional: The name of the Volume to check

=item -P --perf

Flag for performance data output

=item --exclude

Optional: The name of a volume that has to be excluded from the checks (multiple exclude item for multiple volumes)

=item -help

=item -?

to see this Documentation

=back

=head1 EXIT CODE

3 on Unknown Error \
2 if Critical Threshold has been reached \
1 if Warning Threshold has been reached or any problem occured \
0 if everything is ok \

=head1 AUTHORS

 Giorgio Maggiolo <giorgio at maggiolo dot net>
