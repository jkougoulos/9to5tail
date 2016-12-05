#!/usr/bin/perl

use File::Tail;
use MIME::Lite;
use File::stat;
use Getopt::Long;
use DateTime;
use DateTime::Event::Easter;
use Data::Dumper ;
use YAML::Tiny;

use strict;

my $config = ''; 


GetOptions ('config=s' => \$config );

die "no config file given, use --config testlog.yml... " if ( $config eq '' );


$SIG{ALRM} = \&HandleAlarm ;
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
our $filtmodtime ;
our $filterstats ;
our $vacations ;
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
alarm $reportevery;

my $file = File::Tail->new( name => $datafile);

while (defined(my $line = $file->read)) {

	my $skip = 0;
	foreach my $filter ( @filters )
	{
#		print STDERR "TESTING #$filter#..." ;
		if ( $line =~ /$filter/ )
		{	
#			mylog("Got a Hit in filters!\n") ;
			$filterstats->{$filter} += 1;
			$skip = 1;
			last;
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

sub SendReport
{
	my $timessent = 0 ;
	my $subject = "";
        my $now = DateTime->now->set_time_zone( 'local' ) ;
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
		my $vachashref =  $recipient.":".$now->year().":".$now->month().":".$now->day() ;
		if ( !(defined $vacations->{ $vachashref } ) && isNowWorkTime() )
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
}


sub HandleAlarm
{
#	mylog("Got Alarm!\n") ;
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
	#foreach my $filtspec ( keys %{$filterstats} )
	my $k = 1;
	foreach my $filtspec ( @keys )
	{
		my $i = 1;
		foreach my $f ( @filters )
		{
			last if ( $f eq $filtspec );
			$i++;
		}
		mylog( "Hits: ".$filterstats->{ $filtspec }." for <<$filtspec>> currently in pos:$i rank here:$k\n" );
		$k++;
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
		chomp;
		push( @filters, $_ );
	}
	close FH or die "Cannot close $filtfile: $!"; 
	mylog("Found ".scalar(@filters)." filters\n");
}

sub LoadVacations 
{
	open (FH, "< $vacationsfile") or die "Can't open $vacationsfile for read: $!";
	mylog("Loading Vacations\n");
	$vacations = ();
	while ( <FH> )
	{
		chomp;
		next if (! ( /^[a-zA-Z0-9\.\@]+,\d+,\d+,\d+/ ) );
		my @vacdata = split(/,/);
		my $mail = $vacdata[0];
		my $vacyear = int $vacdata[1];
		my $vacmonth = int $vacdata[2];
		my $vacday = int $vacdata[3];
		my $vacstring = $mail.":".$vacyear.":".$vacmonth.":".$vacday ;
		$vacations->{ $vacstring } = "Resting" ;
	}
	close FH or die "Cannot close $vacationsfile: $!"; 
}


sub isNowWorkTime
{
### for testing during weekends coding
#return 1;
### for testing during weekends coding

        my $now = DateTime->now->set_time_zone( 'local' ) ;
# testing #      my $now = DateTime->new( year => 2015, month => 12, day => 24, hour => 12, minute => 31 );

        return 0 if ( $now->day_of_week == 6 || $now->day_of_week == 7 ); # sat sun
        return 0 if ( ( $now->hour() < 9) || ( ( $now->hour() >= 18) && ( $now->min() >= 30) ) || ( $now->hour() >= 18 ) ); # non work hours

        return 0 if ( $now->mon() == 5 && $now->day() == 1 ); # labour day
        return 0 if ( $now->mon() == 5 && $now->day() == 9 ); # Schuman day
        return 0 if ( $now->mon() == 10 && $now->day() == 3 ); # german national holiday

        return 0 if ( $now->mon() == 12 && ( ($now->day() >= 24) && ($now->day() <= 31) ) ); # xmas extended
        return 0 if ( $now->mon() == 1 && ( ( $now->day() == 1 ) || ( $now->day() == 2 ) ) ) ; # new year

        my $maundy_thursday = DateTime::Event::Easter->new( day => -3 );
        my $holy_friday = DateTime::Event::Easter->new( day => -2 );
        my $easter_monday = DateTime::Event::Easter->new( day => 1 );
        my $rosenmontag = DateTime::Event::Easter->new( day => -48 );
        my $whit_monday = DateTime::Event::Easter->new( day => 50 );
        my $ascension = DateTime::Event::Easter->new( day => 39 );
        my $after_ascension = DateTime::Event::Easter->new( day => 40 );
        my $corpus_christi = DateTime::Event::Easter->new( day => 60 );

        return 0 if ( $maundy_thursday->is( $now ) );
        return 0 if ( $holy_friday->is( $now ) );
        return 0 if ( $easter_monday->is( $now ) );
        return 0 if ( $rosenmontag->is( $now ) );
        return 0 if ( $whit_monday->is( $now ) );
        return 0 if ( $ascension->is( $now ) );
#        return 0 if ( $after_ascension->is( $now ) );
        return 0 if ( $corpus_christi->is( $now ) );

        return 1;
}
