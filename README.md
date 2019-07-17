# 9to5tail

A simple perl based script that will spam you with logs, only when you are available!

## Usage
tailer.pl --config configfile.yml

## A few words

It will actually tail -f your logs, ignore the silly things that you don't care about using perl regular expressions that you specify in FilterFile and will send you an email every ReportEverySecs with the stuff you care about, if any of them occured.

Since you don't want to open your email client every morning and spend half an hour reviewing and deleting emails, you can easily (if you know regular expressions) configure your and your coworkers' availability so that the reports follow the available person, your sleeping patterns and your vacations.

## Configuration file
Configuration is specified in yaml format. You may specify multiple recipients, multiple log files and one filter file per instance.

Example:
```
ReportEverySecs: 300
MaxReportBytes: 256000
LogLevel: 1
DataFiles:
        - /var/log/syslog
        - /var/log/fail2ban.log
FilterFile: /var/log/logfilt.testlog
Vacations: tailer.vacations
VacationsTZ: Europe/Berlin
TailerLog: /tmp/tailer.pl.log
FromAddress: realtime.report@domain.dom
Recipients:
        - user1@domain.dom
        - user2@domain.dom
```

## Filter file
format:
```
I:xxxxxxxxxx
  Ignore the xxxxxxxxx pattern (case insensitive)

i:xxxxxxxxxx
  Ignore the xxxxxxxxx pattern (case sensitive)

A:yyyyyyyyyy
  Always include the yyyyyyyy pattern in report (case insensitive)

a:yyyyyyyyyy
  Always include the yyyyyyyy pattern in report (case sensitive)

R,n:zzzzzzzzzz(aaa)zzzzz(bbb)
  Rate calculation (case insensitive)

r,n:zzzzzzzzzz(aaa)zzzzz(bbb)
  Rate calculation (case sensitive)
```

Rate calculation works in the following way:

if the pattern specified after ":" occurs more than "n" times per ReportEverySecs, it will be included on the top of next report

if the pattern captures text using "()", the first 6 captured values will be concatenated to create a key that will be used for (warning, marketing buzzword follows) micro-rate calculation.

Actions A & I operate on a first match basis.

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

##Non-Working time definition
By default, the script assumes that everyone is workaholic, eager to receive emails 24x7.

However, you can change this mindset by configuring the Vacations file.

The file should formatted in the following way:
```
recipientregex1,dateregex1,comment1
recipientregex2,dateregex2,comment2
.
.
.
recipientregexN,dateregexN,commentN
```

Example:
```
.*,.#........#2[23], 22:00 - 23:59 sleep time
.*,.#........#0, 00:00 - 09:59 sleep time
.*,^[67]#,noone will receive on weekends
.*,^.#........#19,noone will receive between 19:00-19:59
.*,^.#....010[12],noone will receive on the first days of new year
.*,#WE-048, noone will receive on Rosen Montag --- 
.*,#WE\+039, Ascension Day
foul,^.#20170516, someone whose email contains the text "foul" will not receive on 16th May 2017
```

Every ReportEverySecs, the script will try to match the recipient and the current date against the defined vacations using the recipient email address and a date string. If a match is found, the report is skipped for the specified recipient.

The date string has the following format (example for 6th January 2107):

When Easter support is NOT activated: 
`5#20170106#174506#CW01`

When Easter support is activated:
`5#20170106#174506#CW01#WE-100#EE-100`

Below is the explanation of the fields:
```
5 -> day of week (1 is Monday, 7 is Sunday) in this case Friday.
# -> delimiter
20170106 -> Date of report... January 6th 2017
# -> delimiter
174506 -> time of the day... 17:45:06 
# -> delimiter. Note: this delimiter and the next charaters can be used only if Easter support is activated, meaning DateTime::Event::Easter is installed in your system
CW -> Calendar week
01 -> 1 (first week of the year, could be 01..53)
# -> delimiter
WE -> Wester Easter
-  -> minus (or + for days after Easter. Easter Sunday is WE+000 )
100 -> 100 days... aka the date of the report is 100 days before western (eg Catholic) Easter. The number of days is always 3 digit (zero pad left).
# -> delimiter
EE -> Eastern Easter
-  -> minus (or + for days after Easter. Easter Sunday is EE+000 )
100 -> 100 days... aka the date of the report is 100 days before eastern (eg Orthodox) Easter. The number of days is always a 3 digit (zero pad left).
```

If no recipient can be reached, the report will be preserved until someone is available.

In the configuration file you can specify also the timezone (see: http://search.cpan.org/dist/DateTime-TimeZone/lib/DateTime/TimeZone/Catalog.pm) of the receivers, or `local` for the machine timezone. This is useful since nowadays the operations people usually live in the same timezone while VMs have the tendency to spread around the world. If you run "follow-the-sun" operations, you can also set the timezone to UTC and do the calculations.


##Miscellaneous
Thanks to File::Tail, you don't have to restart when the log file is rotated

kill -SIGUSR1  will dump in the script's log file (TailerLog) the counters for ignored lines, current calculated rates, allowing you to optimize the order of the filters and gain some speed.

kill -SIGTERM will gracefully terminate the process, sending any pending reports.

kill -HUP will send pending reports and reread FilterFile / Vacations file

MaxReportBytes defines the maximum size of the report mail. Report will be truncated to get an idea of what is happening but you will have to dig in the logs to see what is the problem.

The FilterFile and Vacations file are checked for changes every ReportEverySecs in order to update the filters and vacations without restarting the script. 

Happy log tailing!
