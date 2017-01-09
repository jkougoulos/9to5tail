#!/usr/bin/perl

use File::Tail;
use MIME::Lite;
use File::stat;
use File::Basename;
use Getopt::Long;
use DateTime;
use Data::Dumper ;
use YAML::Tiny;

use strict;

my $config = '';

my $eastersupport = 
	eval {
		require DateTime::Event::Easter;
		DateTime::Event::Easter->import();
		1;
	};

GetOptions ('config=s' => \$config );

die "no config file given, use --config testlog.yml... " if ( $config eq '' );



my $yaml = YAML::Tiny->read( $config );
my $conf = $yaml->[0];

#print Dumper($yaml); die;

my $conffile = $config;
$conffile =~ s/\.yml$//;

my $loglvl = 1;
my $vacationstz = 'local';

my @datafiles = @{ $conf->{ 'DataFiles' } } ;
my $myerrorlog = $conf->{ 'TailerLog' };
my $filtfile = $conf->{ 'FilterFile' };
my $vacationsfile = $conf->{ 'Vacations' };
my $maxreportbytes = $conf->{ 'MaxReportBytes' };
my $reportevery = $conf->{ 'ReportEverySecs' } ;
my $fromaddress = $conf->{ 'FromAddress' };
my @toaddresses = @{ $conf->{ 'Recipients' } } ; 

$loglvl = $conf->{ 'LogLevel' } if ( defined $conf->{ 'LogLevel' } );
$vacationstz = $conf->{ 'VacationsTZ' } if ( defined $conf->{ 'VacationsTZ' } );

my $report = "";
my @filters ;
my $rates ;
my $filtmodtime ;
my $filterstats ;
my @vacations ;
my $vacationsmodtime ;
my $mailssent = 0 ;
my $msgstomail = 0;

my $loadconfig = 0;
my $sendreport = 0;
my $dumpstats = 0;

my @files = ();

Initialize();

alarm $reportevery;
while(1)
{ 
	MainLoop();
	if( $dumpstats )
	{
		my $oldalarm = alarm(0);
		DumpStats();
		$dumpstats = 0;
		alarm $oldalarm;
	}
	if( $sendreport )
	{
		SendReport();
		$sendreport = 0;
		LoadConfig();
		$loadconfig = 0;
		alarm $reportevery;
	}
}

exit(0);

sub MainLoop
{
	my $maxreadblock = 32;

	(my $nfound,my $timeleft,my @pending)= File::Tail::select(undef,undef,undef,undef,@files);

	foreach my $activefile (@pending)
	{
		my $filename = basename( $activefile->{'input'} );
		my $linesread = 0;
		while( $linesread < $maxreadblock && ( ( my $line = $activefile->read ) ne "" ) )
		{
			$linesread++;

#			mylog("TESTING INPUT: LR:$linesread -> $filename : <<$line>>\n",9) ;

			my $skip = 0;

			foreach my $i (0 .. $#filters )
			{
				my $filter = $filters[$i];
	
#				mylog("TESTING FILTER: #$filter#...",9) ;
				my $regex = $filter->{ 'regex' };
				my $casesens = $filter->{ 'casesensitive' };

				if ( $casesens ? ($line =~ /$regex/) : ($line =~ /$regex/i) )
				{	
#					mylog("HIT!\n",9) ;
					$filterstats->{$regex} += 1;

					my $action = $filter->{ 'action' };

					if ( $action eq 'IGNORE' )
					{
				
#						mylog("Action: IGNORE!\n",9) ;
						$skip = 1;
						last;
					}

					if ( $action eq 'ALWAYS' )
					{
#						mylog("Action: ALWAYS!\n",9) ;
						last;
					}

					if ( $action eq 'RATE' )
					{
						my $dynval = "$1:$2:$3:$4:$5:$6" ;
						$dynval =~ s/:+$//g ;
						$dynval = uc($dynval) if( !($casesens) );

#						mylog("Action RATE for <<$regex>> value is #$dynval#\n",9);
						my $key = $i.'+'.$dynval ;
						$rates->{ $key } += 1;
					}
				}
#				mylog("Got a Miss... but we added something in the report\n");
			}
			next if ( $skip );
			if( $#datafiles > 1 )
			{
				$report .=  $filename.':'.$line;
			}
			else
			{
				$report .= $line;
			}
			$msgstomail++;
		}
	}
}

sub Initialize
{
	open ( MYERROR,  ">> $myerrorlog") or die "Can't open $myerrorlog for write: $!";
	select MYERROR; $| = 1;

	mylog("Initializing, will report every $reportevery seconds\n",1);
	foreach my $filepath ( @datafiles )
	{
        	mylog("Data file is: $filepath\n",1);
	}
	mylog("Max report is $maxreportbytes bytes \n",1);
	mylog("Log level is $loglvl\n",1);

	mylog("Initializing Filters\n",1);
	mylog("Filter file is $filtfile\n",1);
	my $statdata = stat( $filtfile ) or die "$filtfile does not exist" ;
	$filtmodtime = $statdata->mtime ;
	mylog("Filter file mtime is: ".$filtmodtime."\n",1) ;
	LoadFilters();

	mylog("Initializing Vacations\n",1);
	my $vacstatdata = stat( $vacationsfile ) or die "$vacationsfile does not exist" ;
	$vacationsmodtime = $vacstatdata->mtime ;
	mylog("Vacations file is: ".$vacationsfile."\n",1) ;
	mylog("Vacations file mtime is: ".$vacationsmodtime."\n",1) ;
	mylog("Vacations TimeZone: ".$vacationstz."\n",1) ;
	LoadVacations();


	if( $eastersupport )
	{
		mylog("Easter support activated!\n",1);
	}
	else
	{
		mylog("Easter support not available, check your vacation file\n",1);
	}

	mylog("Let's start...\n",1) ;

	foreach my $filepath ( @datafiles )
	{
       		push(@files, File::Tail->new( name => $filepath, nowait => 1 ) );
	}

	$SIG{ALRM} = \&HandleAlarm ;
	$SIG{HUP} = \&HandleHup ;
	$SIG{TERM} = \&HandleTermination ;
	$SIG{INT} = \&HandleTermination ;
	$SIG{USR1} = \&HandleStats ;

}

sub mylog
{
        my $msg = $_[0];
        my $msgloglvl = $_[1];
        if( $loglvl >= $msgloglvl )
        {
                print MYERROR localtime()." pid:".$$." tailer ".$conffile.": ".$msg.""
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
	$rates = ();
}


sub SendReport
{
	my $timessent = 0 ;
	my $subject = "";


#	mylog("SendReport!\n",1);

	AddRatesInReport();

	if ( $report eq "" )
	{
		mylog("Nothing to report!\n",4);
		return;
	}

	if ( length( $report ) > $maxreportbytes )
	{
		$report = substr( $report, 0, $maxreportbytes );
		$subject = $conffile.' Realtime syslog report TRUNCATED, Check logs!';
	}
	else
	{
		$subject = $conffile.' Realtime syslog report ' ;
	}
	foreach my $recipient ( @toaddresses )
	{

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
			mylog("Just sent an email to $recipient!\n",3);
		}
		else
		{
			mylog( $recipient." is on vacation... or we don't work now... lets not spam!\n",3);
		}
	}
	if ( $timessent > 0 )   # keep the report if everyone is on vacation... but we will not send a report even if we are dying...
	{
		$report = "";
		$msgstomail = 0;
	}
}

sub LoadConfig
{
	mylog("In LoadConfig\n",5);
	my $statdata = stat( $filtfile ) or die "$filtfile does not exist" ;
	if ( $statdata->mtime ne $filtmodtime )
	{
		mylog("Filters have changed new mtime is ".$statdata->mtime."!\n",1);
		LoadFilters();
		$filtmodtime = $statdata->mtime ;
	}

	my $vacstatdata = stat( $vacationsfile ) or die "$vacationsfile does not exist" ;
	if ( $vacstatdata->mtime ne $vacationsmodtime )
	{
		mylog("Vacations have changed new mtime is ".$vacstatdata->mtime."!\n",1);
		LoadVacations();
		$vacationsmodtime = $vacstatdata->mtime ;
	}
}

sub HandleHup
{
	alarm 0;
	$sendreport = 1;
	$loadconfig = 1;
}

sub HandleAlarm
{
	$sendreport = 1;
	$loadconfig = 1;
}

sub HandleStats
{
	$dumpstats = 1;
}

sub DumpStats
{
	mylog( "Dumping filtered messages stats \n",1);

	my @keys = sort { $filterstats->{$b} <=> $filterstats->{$a} } keys %{$filterstats}; # sort by hash value
	
	my $k = 0;
	foreach my $filtspec ( @keys )
	{
		my $i = 0;
		foreach my $f ( @filters )
		{
			last if ( $f->{ 'regex' }  eq $filtspec );
			$i++;
		}
		mylog( "Hits: ".$filterstats->{ $filtspec }." for <<$filtspec>> currently in pos:$i rank here:$k\n",1);
		$k++;
	}
	foreach my $key ( keys %$rates )
	{
		mylog( "RATE key $key has ".$rates->{ $key }." hits\n",1);
	}

	mylog( "We have sent $mailssent emails\n",1);
	mylog( "We have $msgstomail messages in buffer to be sent!\n",1);
	mylog( "End of dump!\n",1);
}

sub HandleTermination
{
	alarm 0;
	mylog("Caught termination ( SIGINT || SIGTERM ) signal!...need to cleanup\n",1);
	mylog("Sending the final report before terminating!\n",1);

	SendReport();

	mylog("Let's die peacefully!\n",1);
	close MYERROR or die "Cannot close $myerrorlog: $!";;
	exit(0);
}

sub re_valid 
{
    my $re = eval { qr/$_[0]/ };
    defined($re) ? 1 : 0 ;
}

sub LoadFilters 
{
	open (FH, "< $filtfile") or die "Can't open $filtfile for read: $!";
	mylog("Loading Filters\n",1);
	@filters = ();
	while ( <FH> )
	{
		my $filter = ();
		
		chomp;
		my $filterline = $_ ;
		if( $filterline =~ /^I:(.*)$/i )
		{
			$filter->{ 'action' } = 'IGNORE' ;
			my $regex = $1;

			if ( $filterline =~ /^i/ )
			{
				$filter->{ 'casesensitive' } = 1;
			}
			else
			{
				$filter->{ 'casesensitive' } = 0;
			}
			
			if( re_valid($regex) )
			{
				$filter->{ 'regex' } = $regex ;
				push( @filters, $filter );
			}
			else
			{
				mylog("Ignoring <<$regex>>, Not Valid regex\n",2);
			}
			next;
		}

		if( $filterline =~ /^A:(.*)$/i )
		{
			$filter->{ 'action' } = 'ALWAYS' ;
			my $regex = $1;

			if ( $filterline =~ /^a/ )
			{
				$filter->{ 'casesensitive' } = 1;
			}
			else
			{
				$filter->{ 'casesensitive' } = 0;
			}
			
			if( re_valid($regex) )
			{
				$filter->{ 'regex' } = $regex ;
				push( @filters, $filter );
			}
			else
			{
				mylog("Ignoring <<$regex>>, Not Valid regex\n",2);
			}
			next;
		}

		if( $filterline =~ /^R,([0-9]+):(.*)$/i )
		{
			$filter->{ 'action' } = 'RATE' ;
			$filter->{ 'threshold' } = $1 ;
			my $regex = $2;

			if ( $filterline =~ /^r/ )
			{
				$filter->{ 'casesensitive' } = 1;
			}
			else
			{
				$filter->{ 'casesensitive' } = 0;
			}
			
			if( re_valid($regex) )
			{
				$filter->{ 'regex' } = $regex ;
				push( @filters, $filter );
			}
			else
			{
				mylog("Ignoring <<$regex>>, Not Valid regex\n",2);
			}
			next;
		}

		mylog( "Ignoring <<$filterline>>\n",1);
	}
	close FH or die "Cannot close $filtfile: $!"; 
	mylog("Found ".scalar(@filters)." filters\n",1);
}

sub LoadVacations 
{
	open (FH, "< $vacationsfile") or die "Can't open $vacationsfile for read: $!";
	mylog("Loading Vacations\n",1);
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
        my $now = DateTime->now->set_time_zone( $vacationstz ) ;

#UNCOMMENT below for vacation testing
	#my $now = DateTime->new( 
	#                               'year' => 2018,
	#                               'month' => 2,
	#                               'day' => 12
	#);

	my $cw = sprintf( "%02d", $now->week_number()) ;
	my $nowstr = $now->dow()."#".$now->ymd('')."#".$now->hms('').'#CW'.$cw;

	if ( $eastersupport )
	{
		my $weaster = DateTime::Event::Easter->new( easter => 'western' );
		my $eeaster = DateTime::Event::Easter->new( easter => 'eastern' );

		my $firstdayofthisyear = DateTime->new( 
                                        year => $now->year(),
                                        month => 1,
                                        day => 1
                                        )->set_time_zone( $vacationstz );

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

	mylog( "recipient is $recipient, now is $nowstr\n",4);

	foreach my $vacation ( @vacations )
	{
		if ( $recipient =~ /$vacation->{ 'recipientregex' }/i )
		{
			if ( $nowstr =~ /$vacation->{ 'dateregex' }/i )
			{
				mylog( "Skipping report to $recipient due to #".$vacation->{ 'comment' }."#\n",4);
				return 0;
			}
		}
	}

	return 1;
}
