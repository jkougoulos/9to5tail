# 9to5tail

###please use tag v0.1, master unstable

A simple perl based script that will spam you with logs. It will actually tail -f your log, ignore the silly things that you don't care about using perl regex specified in FilterFile (like running "egrep -v -f Filterfile DataFile") and will send you an mail every ReportEverySecs with the important stuff during working hours.

##Configuration file
Configuration is specified in yaml format (see testlog.yml). You may specify multiple recipients, one log file and one filter file per instance.

##Filter file
format:
I:xxxxxxxxxx
  Ignore the xxxxxxxxx pattern

A:yyyyyyyyyy
  Always include the yyyyyyyy pattern in report

R,n:zzzzzzzzzz(aaa)zzzzz(bbb)
  Rate calculation: 

if the pattern specified after ":" occurs more than "n" times per ReportEverySecs, it will be included on the top of next report

if the pattern captures text using "()", the first 6 captured values will be concatenated to create a key that will be used for micro-rate calculation (hahaha I should work in marketing).

Actions A & I operate on a first match basis and subsequent matches will be ignored
Action R will just update counters on match and further matching will continue (for further R actions, I or A).

eg.
consider the following logs from a switch:
```
Jan  6 10:44:04 10.4.2.5 979748: Jan  6 10:44:03.405: %MAB-SW1-5-FAIL: Authentication failed for client (ac57.acc9.9813) on Interface Gi117/2/0/39 AuditSessionID 0A30FE01000062523E6FDEC4
Jan  6 10:44:29 10.4.2.5 979751: Jan  6 10:44:28.031: %MAB-SW1-5-FAIL: Authentication failed for client (00b3.cd28.36a7) on Interface Gi164/2/0/33 AuditSessionID 0A30FE010000642941CF9DEC
Jan  6 10:44:32 10.4.2.5 979752: Jan  6 10:44:31.111: %MAB-SW1-5-FAIL: Authentication failed for client (00b3.cd28.36a7) on Interface Gi164/2/0/33 AuditSessionID 0A30FE010000642941CF9DEC
```

if the Filter file contains these lines:
```
R,3:%MAB-SW1-5-FAIL: Authentication failed for client \(([a-f0-9\.]+)\) on Interface
I:%MAB-SW1-5-FAIL
```

a message will appear on the report only when the log message with the same mac address appears more than 3 times every ReportEverySecs

##Working time definition
Non working time is defined in sub "isNowWorkTime", return 0 for non working time. Adjust as needed.

eg #1:

```
return 0 if ( ( $now->hour() < 9) || ( $now->hour() >= 18 ) || ( ( $now->hour() == 18) && ( $now->min() >= 30) ) ); 
```

defines that mails will not be sent between 18:30 - 09:00

eg #2
```
return 0 if ( $now->day_of_week == 6 || $now->day_of_week == 7 );
```

defines that emails will not be sent during weekends

in Vacations file you may specify the vacation days of the recipients so that they don't get spammed while relaxing, in the format :
email, year, month, day

##Miscellaneous
Thanks to File::Tail, you don't have to restart when the log file is rotated

kill -SIGUSR1  will dump in the script's log file (TailerLog) the counters for ignored lines, allowing you to optimize the order of the filters and gain some speed.

kill -SIGTERM will gracefully terminate the process, sending any pending reports.

kill -HUP will send pending reports and reread FilterFile / Vacations file

MaxReportBytes defines the maximum size of the report mail. Report will be truncated to get an idea of what is happening but you will have to dig in the logs to see what is the problem.

The FilterFile and Vacations file are checked for changes every ReportEverySecs in order to update the filters and vacations without restarting the script.

Happy log watching!
