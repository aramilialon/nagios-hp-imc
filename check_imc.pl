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
			"switch=s" => \my $switch_name,
			'h|help' => sub { exec perldoc => -F => $0 or die "Cannot execute perldoc: $!\n"; }
) or Error("$0: Error in command line arguments\n");

sub Error {
    print "$0: " . $_[0] . "\n";
    exit 2;
}

sub license_check {
	my $function = "plat/licenseInfo/allLicenseMsg";
	my $xml_response = get_xml_text($function);
	my $dom = XML::LibXML->load_xml(string => $xml_response->content);
	print $dom->getElementsByTagName("list")->get_node(1)->getElementsByTagName("licenseInfo")->get_node(1)->getElementsByTagName("comDisplayName")->string_value();
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

Error('Option --server required') unless $server;
Error('Option --username required') unless $username;
Error('Option --password required') unless $password;


$realm = "iMC RESTful Web Services" unless $realm;
$port = "8080" unless $port;

my $rest_call;

if($operation eq "license_check"){
	$rest_call = license_check();
}


__END__

=head1 NAME

check_hp_imc - Check HPE iMC environment

=head1 SYNOPSIS

check_hp_imc.pl --server SERVER_IP --username USERNAME --password PASSWORD \
		[--port PORT] --operation OPERATION [--switch SWITCH_NAME] [-h|--help] 

=head1 DESCRIPTION

Connects to a HPE iMC and performe some operations with it. \
It can be used to retrieve the managed devices status, for example

=head1 OPTIONS

=over 4

=item --server SERVER

FQDN or IP Address of the HPE iMC

=item -u | --username USERNAME

The Username to be used

=item -p | --password PASSWORD

The Login Password of the NetApp to monitor

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

3 on Unknown Error
2 if Critical Threshold has been reached
1 if Warning Threshold has been reached or any problem occured
0 if everything is ok

=head1 AUTHORS

 Giorgio Maggiolo <giorgio at maggiolo dot net>
