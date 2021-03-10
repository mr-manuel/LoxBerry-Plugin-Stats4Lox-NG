use LoxBerry::Log;
use LoxBerry::JSON;
use XML::LibXML;
use XML::LibXML::Common;
use warnings;
use strict;
use Encode;
# use open ':std', ':encoding(UTF-8)';

# Debugging
use Data::Dumper;

package Loxone::ParseXML;


#####################################################
# Read LoxPLAN XML
#####################################################

# What you get:
# - Key of the hash is UUID
# - Every key contains
	# {Title} Object name (Bezeichnung)
	# {Desc} Object description (Beschreibung). If empty--> Object name (*)
	# {StatsType} Statistics type 1..7
	# {Type} Type name of the Loxone input/output/function
	# {MSName} Name of the Miniserver
	# {MSIP} IP of the Miniserver
	# {MSNr} ID of the Miniserver in LoxBerry General Config
	# {Unit} Unit to display in the Loxone App (stripped from Loxone syntax <v.1>)
	# {Category} Name of the category
	# {Place} Name of the place (room)
	# {MinVal} Defined minimum value or string 'U' for undefined
	# {MaxVal} Defined maximum value or string 'U' for undefined


# ARGUMENTS are named parameters
# filename ... the LoxPlan XML
# log ... Log object (LoxBerry::Log - send using \$logobj)
# RETURNS
# Hashref with parsed data

sub readloxplan
{
	
	my %args = @_;
		
	my $loxconfig_path;
	my $log;
	my @loxconfig_xml;
	my %lox_miniserver;
	my %lox_category;
	my %lox_room;
	my $start_run = time();
	my %lox_statsobject; 
	#my %cfg_mslist;

	$loxconfig_path = $args{filename};
	$log = $args{log};

	
	# For performance, it would be possibly better to switch from XML::LibXML to XML::Twig

	# Prepare data from LoxPLAN file
	#my $parser = XML::LibXML->new();
	our $lox_xml;
	my $parser;
	eval { 
		my $xmlstr = LoxBerry::System::read_file($loxconfig_path);
		
		# LoxPLAN uses a BOM, that cannot be handled by the XML Parser
		my $UTF8_BOM = chr(0xef) . chr(0xbb) . chr(0xbf);
		if(substr( $xmlstr, 0, 3) eq $UTF8_BOM) {
			$log->INF("Removing BOM of LoxPLAN input");
			$xmlstr = substr $xmlstr, 3;
		}
		$xmlstr = Encode::encode("utf8", $xmlstr);
		$lox_xml = XML::LibXML->load_xml( string => $xmlstr );
	};
	if ($@) {
		$log->ERR( "import.cgi: Cannot parse LoxPLAN XML file: $@");
		#exit(-1);
		return;
	}

	# Read Loxone Miniservers
	foreach my $miniserver ($lox_xml->findnodes('//C[@Type="LoxLIVE"]')) {
		# Use an multidimensional associative hash to save a table of necessary MS data
		# key is the Uid
		$lox_miniserver{$miniserver->{U}}{Title} = $miniserver->{Title};
		$lox_miniserver{$miniserver->{U}}{Serial} = $miniserver->{Serial};
		
		# IP address can hava a port
		my ($msxmlip, $msxmlport) = split(/:/, $miniserver->{IntAddr}, 2);
		if($msxmlip=~/^(\d{1,3}).(\d{1,3}).(\d{1,3}).(\d{1,3})$/ &&(($1<=255 && $2<=255 && $3<=255 &&$4<=255 ))) { 
			# IP seems valid
			$log->DEB( "Found Miniserver $miniserver->{Title} with IP $msxmlip");
			$lox_miniserver{$miniserver->{U}}{IP} = $msxmlip;
		} elsif ((! defined $msxmlip) || ($msxmlip eq "")) {
			$log->ERR( "Miniserver $miniserver->{Title}: Internal IP is empty. This field is mandatory. Please update your Config.");
			$lox_miniserver{$miniserver->{U}}{IP} = undef;
		} else { 
			# IP seems not to be an IP - possibly we need a DNS lookup?
			$log->WARN( "Found Miniserver $miniserver->{Title} possibly configured with hostname. Querying IP of $msxmlip ...");
			my $dnsip = inet_ntoa(inet_aton($msxmlip));
			if ($dnsip) {
				$log->WARN( " --> Found Miniserver $miniserver->{Title} and DNS lookup got IP $dnsip ...");
				$lox_miniserver{$miniserver->{U}}{IP} = $dnsip;
			} else {
				$log->ERR( " --> Could not find an IP for Miniserver $miniserver->{Title}. Giving up this MS. Please check the internal Miniserver IPs in your Loxone Config.");
				$lox_miniserver{$miniserver->{U}}{IP} = $msxmlip;
			}
		}
		# In a later stage, we have to query the LoxBerry MS Database by IP to get LoxBerrys MS-ID.
	}

	# Read Loxone categories
	foreach my $category ($lox_xml->findnodes('//C[@Type="Category"]')) {
		# Key is the Uid
		$lox_category{$category->{U}} = $category->{Title};
	}
	# print "Test Perl associative array: ", $lox_category{"0b2c7aea-007c-0002-0d00000000000000"}, "\r\n";

	# Read Loxone rooms
	foreach my $room ($lox_xml->findnodes('//C[@Type="Place"]')) {
		# Key is the Uid
		$lox_room{$room->{U}} = $room->{Title};
	}

	# Get all objects that have statistics enabled
	#my $hr = HTML::Restrict->new();
			
	foreach my $object ($lox_xml->findnodes('//C[@StatsType]')) {
		# Get Miniserver of this object
		# Nodes with statistics may be a child or sub-child of LoxLive type, or alternatively Ref-er to the LoxLive node. 
		# Therefore, we have to distinguish between connected in some parent, or referred by in some parent.	
		my $ms_ref;
		my $parent = $object;
		do {
			$parent = $parent->parentNode;
		} while ((!$parent->{Ref}) && ($parent->{Type} ne "LoxLIVE"));
		if ($parent->{Type} eq "LoxLIVE") {
			$ms_ref = $parent->{U};
		} else {
			$ms_ref = $parent->{Ref};
		}
		$log->DEB("Objekt: " . $object->{Title} . " (StatsType = " . $object->{StatsType} . ") | Miniserver: " . $lox_miniserver{$ms_ref}{Title});
		$lox_statsobject{$object->{U}}{Title} = $object->{Title};
		if (defined $object->{Desc}) {
			$lox_statsobject{$object->{U}}{Desc} = $object->{Desc}; }
		else {
			$lox_statsobject{$object->{U}}{Desc} = $object->{Title} . " (*)"; 
		}
		$lox_statsobject{$object->{U}}{StatsType} = $object->{StatsType};
		$lox_statsobject{$object->{U}}{Type} = $object->{Type};
		$lox_statsobject{$object->{U}}{MSName} = $lox_miniserver{$ms_ref}{Title};
		$lox_statsobject{$object->{U}}{MSIP} = $lox_miniserver{$ms_ref}{IP};
		# $lox_statsobject{$object->{U}}{MSNr} = $cfg_mslist{$lox_miniserver{$ms_ref}{IP}};
		$lox_statsobject{$object->{U}}{MSNr} = LoxBerry::System::get_miniserver_by_ip( $lox_miniserver{$ms_ref}{IP} );
		
		# Unit
		my @display = $object->getElementsByTagName("Display");
		if($display[0]->{Unit}) { 
			$lox_statsobject{$object->{U}}{Unit} = $display[0]->{Unit};
			$lox_statsobject{$object->{U}}{Unit} =~ s|<.+?>||g;
			$lox_statsobject{$object->{U}}{Unit} = LoxBerry::System::trim($lox_statsobject{$object->{U}}{Unit});
			$log->DEB( "Unit: " . $lox_statsobject{$object->{U}}{Unit});
		} else { 
			$log->DEB( "Unit: (none detected)");
		}
		
		# Place and Category
		my @iodata = $object->getElementsByTagName("IoData");
		$log->DEB( "Cat: " . $lox_category{$iodata[0]->{Cr}});
		$lox_statsobject{$object->{U}}{Category} = $lox_category{$iodata[0]->{Cr}} if ($iodata[0]->{Cr});
		$lox_statsobject{$object->{U}}{Place} = $lox_room{$iodata[0]->{Pr}} if ($iodata[0]->{Pr});
		
		# Min/Max values
		if ($object->{Analog} and $object->{Analog} ne "true") {
			$lox_statsobject{$object->{U}}{MinVal} = 0;
			$lox_statsobject{$object->{U}}{MaxVal} = 1;
		} else {
			if ($object->{MinVal}) { 
				$lox_statsobject{$object->{U}}{MinVal} = $object->{MinVal};
			} else {
				$lox_statsobject{$object->{U}}{MinVal} = "U";
			}
			if ($object->{MaxVal}) { 
				$lox_statsobject{$object->{U}}{MaxVal} = $object->{MaxVal};
			} else {
				$lox_statsobject{$object->{U}}{MaxVal} = "U";
			}
		}
		$log->DEB( "Object Name: " . $lox_statsobject{$object->{U}}{Title});
	}
	
	
	my $end_run = time();
	my $run_time = $end_run - $start_run;
	# print "Job took $run_time seconds\n";
	return \%lox_statsobject;
}

#############################################################################
# Creates a json file from the Loxone XML
#############################################################################
# ARGUMENTS are named parameters
# filename ... the LoxPlan XML
# output ... the filename of the resulting json file
# log ... Log object (LoxBerry::Log - send using \$logobj)
# RETURNS
# - undef on error
# - !undef on ok

sub loxplan2json
{
	my %args = @_;
	my $log = $args{log};
	
	$log->INF("loxplan2json started") if ($log);
	
	eval {
		
		my $result = readloxplan( log => $args{log}, filename => $args{filename} );
		if (!$result) {
			$log->CRIT("Error parsing XML");
			return undef;
		}
		
		unlink $args{output};
		my $jsonparser = LoxBerry::JSON->new();
		my $loxplanjson = $jsonparser->open(filename => $args{output});
		$loxplanjson->{loxplan} = $result;
		$jsonparser->write();
	
	};
	if ($@) {
		print STDERR "loxplan2json: Error running procedure: $@\n";
		$log->ERR("loxplan2json: Error running procedure: $@\n") if ($log);
		return undef;
	}
	
	return 1;

}


#####################################################
# Finally 1; ########################################
#####################################################
1;
