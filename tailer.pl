#!/usr/bin/perl

use File::Tail;
use MIME::Lite;
use File::stat;
use Getopt::Long;
use DateTime;
use Data::Dumper ;
use YAML::Tiny;

use strict;

my $config = '';

our $eastersupport = 
	eval {
		require DateTime::Event::Easter;
		DateTime::Event::Easter->import();
		1;
	};

GetOptions ('config=s' => \$config );

die "no config file given, use --config testlog.yml... " if ( $config eq '' );


$SIG{ALRM} = \&HandleAlarm ;
$SIG{HUP} = \&HandleAlarm ;
$SIG{TERM} = \&HandleTermination ;
$SIG{INT} = \&HandleTermination ;
$SIG{USR1} = \&HandleStats ;

my $yaml = YAML::Tiny->read( $config );
my $conf = $yaml->[0];

#print Dumper($yaml); die;

my $logfile = $config;
$logfile =~ s/\.yml$//;

my $datafile = $conf->{ 'DataFile' } ;
my $myerrorlog = $conf->{ 'TailerLog' };
my $filtfile = $conf->{ 'FilterFile' };
my $vacationsfile = $conf->{ 'Vacations' };
my $maxreportbytes = $conf->{ 'MaxReportBytes' };

our $report = "";
our $reportevery = $conf->{ 'ReportEverySecs' } ;
our $fromaddress = $conf->{ 'FromAddress' };
our @toaddresses = @{ $conf->{ 'Recipients' } } ; 
our @filters ;
our $rates ;
our $filtmodtime ;
our $filterstats ;
our @vacations ;
our $vacationsmodtime ;
our $mailssent = 0 ;
our $msgstomail = 0;

open ( MYERROR,  ">> $myerrorlog") or die "Can't open $myerrorlog for write: $!";
select MYERROR; $| = 1;

mylog("Initializing, will report every $reportevery seconds\n");
mylog("Data file is $datafile\n");
mylog("Filter file is $filtfile\n");
mylog("Max report is $maxreportbytes bytes \n");

mylog("Initializing Filters\n");
my $statdata = stat( $filtfile ) or die "$filtfile does not exist" ;
$filtmodtime = $statdata->mtime ;
mylog("Filter file mtime is: ".$filtmodtime."\n") ;
LoadFilters();

mylog("Initializing Vacations\n");
my $vacstatdata = stat( $vacationsfile ) or die "$vacationsfile does not exist" ;
$vacationsmodtime = $vacstatdata->mtime ;
mylog("Vacations file is: ".$vacationsfile."\n") ;
mylog("Vacations file mtime is: ".$vacationsmodtime."\n") ;
LoadVacations();

mylog("Let's start...\n") ;

if( $eastersupport )
{
	mylog("Easter support activated!\n");
}
else
{
	mylog("Easter support not available, check your vacation file\n");
}

alarm $reportevery;

my $file = File::Tail->new( name => $datafile);

while (defined(my $line = $file->read)) {

	my $skip = 0;

	foreach my $i (0 .. $#filters )
	{
		my $filter = $filters[$i];
	
#		print STDERR "TESTING #$filter#..." ;
		my $regex = $filter->{ 'regex' };
		if ( $line =~ /$regex/ )
		{	
#			mylog("Got a Hit in filters!\n") ;
			$filterstats->{$regex} += 1;

			my $action = $filter->{ 'action' };
			if ( $action eq 'IGNORE' || $action eq 'ALWAYS' )
			{
				$skip = 1  if( $action eq 'IGNORE' );
				last;
			}
			if ( $action eq 'RATE' )
			{
				my $dynval = "$1:$2:$3:$4:$5:$6" ;
				$dynval =~ s/:+$//g ;
#				mylog("RATE for <<$regex>> value is #$dynval#\n");
				my $key = $i.'+'.$dynval ;
				if ( defined $rates->{ $key } )
				{
					$rates->{ $key } += 1;
				}
				else
				{
					$rates->{ $key } = 1;
				}
				$skip = 1;
#				mylog( "RATE for key ".$key." is now ".$rates->{ $key }."\n" );
			}
		}
#		mylog("Got a Miss... but we added something in the report\n");
	}
	next if ( $skip );
	$report .=  $line;
	$msgstomail++;
}

sub mylog
{
        my $msg = $_[0];
#        my $msgloglvl = $_[1];
#        if( $loglvl >= $msgloglvl )
        {
                print MYERROR localtime()." pid:".$$." tailer ".$logfile.": ".$msg.""
        }
}

sub AddRatesInReport
{

        my $now = DateTime->now->set_time_zone( 'local' ) ;
	foreach my $rate ( keys %$rates )
	{
		my ($filterid, $dynval) = $rate =~ /([0-9]+)\+(.*)/ ;
		my $filter = $filters[$filterid];
		my $threshold = $filter->{ 'threshold' };
		my $rateval = $rates->{ $rate } ;

		if ( $rateval > $threshold )
		{
			my $regex = $filter->{ 'regex' };
			my $msg = $now." RATEMATCH: VAL:$rateval THR:$threshold VALUE:#$dynval# PATTERN:<<$regex>>\n";
			$report = $msg.$report
		}
	}
}


sub SendReport
{
	my $timessent = 0 ;
	my $subject = "";


	if ( length( $report ) > $maxreportbytes )
	{
		$report = substr( $report, 0, $maxreportbytes );
		$subject = $logfile.' Realtime syslog report TRUNCATED, Check logs!';
	}
	else
	{
		$subject = $logfile.' Realtime syslog report ' ;
	}
	foreach my $recipient ( @toaddresses )
	{

#		if ( !(defined $vacations->{ $vachashref } ) && isNowWorkTime() )
		if ( isNowWorkTime( $recipient ) ) 
		{
			my $msg = MIME::Lite->new(
		       		From     => $fromaddress,
		        	To       => $recipient,
#		        	Cc       => 'some@other.com, some@more.com',
		        	Subject  => $subject,
		        	Data     => $report
			);
			$msg->send;
			$timessent++;
			$mailssent++;
#			mylog("Just sent an email!\n");
		}
		else
		{
#			mylog( $recipient." is on vacation... or we don't work now... lets not spam!\n" );
		}
	}
	if ( $timessent > 0 )   # keep the report if everyone is on vacation... but we will not send a report even if we are dying...
	{
		$report = "";
		$msgstomail = 0;
	}
	$rates = ();
}


sub HandleAlarm
{
	alarm 0;
#	mylog("Got Alarm!\n") ;
	AddRatesInReport();
	if ( $report ne "" )
	{
		SendReport();
	}
	else
	{	
#		mylog("Nothing to report!\n");
	}
	my $statdata = stat( $filtfile ) or die "$filtfile does not exist" ;
	if ( $statdata->mtime ne $filtmodtime )
	{
		mylog("Filters have changed new mtime is ".$statdata->mtime."!\n");
		LoadFilters();
		$filtmodtime = $statdata->mtime ;
	}

	my $vacstatdata = stat( $vacationsfile ) or die "$vacationsfile does not exist" ;
	if ( $vacstatdata->mtime ne $vacationsmodtime )
	{
		mylog("Vacations have changed new mtime is ".$vacstatdata->mtime."!\n");
		LoadVacations();
		$vacationsmodtime = $vacstatdata->mtime ;
	}
	alarm $reportevery;
}

sub HandleStats
{
	mylog( "Caught SIGUSR1... Dumping filtered messages stats \n" );
	my @keys = sort { $filterstats->{$b} <=> $filterstats->{$a} } keys %{$filterstats}; # sort by hash value
	
	my $k = 1;
	foreach my $filtspec ( @keys )
	{
		my $i = 1;
		foreach my $f ( @filters )
		{
			last if ( $f->{ 'regex' }  eq $filtspec );
			$i++;
		}
		mylog( "Hits: ".$filterstats->{ $filtspec }." for <<$filtspec>> currently in pos:$i rank here:$k\n" );
		$k++;
	}
	foreach my $key ( keys %$rates )
	{
		mylog( "RATE key $key has ".$rates->{ $key }." hits\n" );
	}

	mylog( "Sent $mailssent emails\n");
	mylog( "We have $msgstomail messages in buffer to be sent!\n" );
	mylog( "End of dump!\n" );
}

sub HandleTermination
{
	alarm(0);
	mylog("Caught termination ( SIGINT || SIGTERM ) signal!...need to cleanup\n");
	if ( $report ne "" )
	{
		mylog("Sending the final report before terminating!\n");
		AddRatesInReport();
		SendReport();
	}
	mylog("Let's die peacefully!\n");
	close MYERROR or die "Cannot close $myerrorlog: $!";;
	exit(0);
}


sub LoadFilters 
{
	open (FH, "< $filtfile") or die "Can't open $filtfile for read: $!";
	mylog("Loading Filters\n");
	@filters = ();
	while ( <FH> )
	{
		my $filter = ();
		
		chomp;
		my $filterline = $_ ;
		if( $filterline =~ /^I:(.*)$/i )
		{
			$filter->{ 'action' } = 'IGNORE' ;
			$filter->{ 'regex' } = $1 ;
			push( @filters, $filter );
			next;
		}

		if( $filterline =~ /^A:(.*)$/i )
		{
			$filter->{ 'action' } = 'ALWAYS' ;
			$filter->{ 'regex' } = $1 ;
			push( @filters, $filter );
			next;
		}

		if( $filterline =~ /^R,([0-9]+):(.*)$/i )
		{
			$filter->{ 'action' } = 'RATE' ;
			$filter->{ 'regex' } = $2 ;
			$filter->{ 'threshold' } = $1 ;
			push( @filters, $filter );
			next;
		}

		mylog( "Ignoring $filterline \n" );
	}
	close FH or die "Cannot close $filtfile: $!"; 
	mylog("Found ".scalar(@filters)." filters\n");
}

sub LoadVacations 
{
	open (FH, "< $vacationsfile") or die "Can't open $vacationsfile for read: $!";
	mylog("Loading Vacations\n");
	@vacations = ();
	while ( <FH> )
	{
		chomp;
		
		my $vacation = ();
		my @vacdata = split(/,/);
		
		$vacation->{ 'recipientregex' } = $vacdata[0];
		$vacation->{ 'dateregex' } = $vacdata[1];
		$vacation->{ 'comment' } = $vacdata[2];
		push( @vacations, $vacation );
	}
	close FH or die "Cannot close $vacationsfile: $!"; 
}


sub isNowWorkTime
{
	my $recipient = $_[0];


#COMMENT below for vacation testing
        my $now = DateTime->now->set_time_zone( 'local' ) ;

#UNCOMMENT below for vacation testing
	#my $now = DateTime->new( 
	#                               'year' => 2018,
	#                               'month' => 2,
	#                               'day' => 12
	#);

	my $nowstr = $now->dow()."#".$now->ymd('')."#".$now->hms('');

	if ( $eastersupport )
	{
		my $weaster = DateTime::Event::Easter->new( easter => 'western' );
		my $eeaster = DateTime::Event::Easter->new( easter => 'eastern' );

		my $firstdayofthisyear = DateTime->new( 
                                        year => $now->year(),
                                        month => 1,
                                        day => 1
                                        );

		my $weasterthisyear = $weaster->following( $firstdayofthisyear );
		my $eeasterthisyear = $eeaster->following( $firstdayofthisyear );

		my $wedelta = $now->delta_days( $weasterthisyear )->delta_days();
		my $eedelta = $now->delta_days( $eeasterthisyear )->delta_days();

		my $wesign = '+';
		my $eesign = '+';

		$wesign = '-' if ( DateTime->compare( $now, $weasterthisyear ) < 0 );
		$eesign = '-' if ( DateTime->compare( $now, $eeasterthisyear ) < 0 );

		my $wedeltastr = sprintf( "%03d", $wedelta) ;
		my $eedeltastr = sprintf( "%03d", $eedelta) ;

		$nowstr .= "#WE$wesign$wedeltastr#EE$eesign$eedeltastr";
	}

#	mylog( "recipient is $recipient, now is $nowstr\n" );

	foreach my $vacation ( @vacations )
	{
		if ( $recipient =~ /$vacation->{ 'recipientregex' }/i )
		{
			if ( $nowstr =~ /$vacation->{ 'dateregex' }/i )
			{
#				mylog( "Skipping report to $recipient due to #".$vacation->{ 'comment' }."#\n" );
				return 0;
			}
		}
	}

	return 1;
}
