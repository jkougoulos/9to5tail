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
Non working time is defined in through Vacations file

the format of the  file is the following:
```
recipientregex,dateregex,comment
```

Every ReportEverySecs, the script will check the defined vacations using the recipient address and a date string. If a match is found, the report is skipped for the specified recipient.

The date string has the following format (example for 6th January 2107):

When Easter support is NOT activated: 
`5#20170106#174506`

When Easter support is activated:
`5#20170106#174506#WE-100#EE-100`

Below is the explanation of the fields:
```
5 -> day of week (1 is Monday, 7 is Sunday) in this case Friday.
# -> delimiter
20170106 -> Date of report... January 6th 2017
# -> delimiter
174506 -> time of the day... 17:45:06 
# -> delimiter. Note: this delimiter and the next charaters can be used only if Easter support is activated, meaning DateTime::Event::Easter is installed in your system
WE -> Wester Easter
-  -> minus
100 -> 100 days... aka the date of the report is 100 days before western (eg Catholic) Easter
# -> delimiter
EE -> Eastern Easter
-  -> minus
100 -> 100 days... aka the date of the report is 100 days before western (eg Orthodox) Easter
```

by adjusting the date regex you may define when the recipients should NOT receive the reports.
eg:
```
.*,^[67]#,noone will receive on weekends
.*,^.#........#19,noone will receive between 19:00-19:59
.*,^.#....010[12],noone will receive on the first days of new year
.*,#WE-048, noone will receive on Rosen Montag --- 
.*,#WE\+039, Ascension Day
foul,^.#20170516, someone whose email contains the text "foul" will not receive on 16th May 2017
```

##Miscellaneous
Thanks to File::Tail, you don't have to restart when the log file is rotated

kill -SIGUSR1  will dump in the script's log file (TailerLog) the counters for ignored lines, allowing you to optimize the order of the filters and gain some speed.

kill -SIGTERM will gracefully terminate the process, sending any pending reports.

kill -HUP will send pending reports and reread FilterFile / Vacations file

MaxReportBytes defines the maximum size of the report mail. Report will be truncated to get an idea of what is happening but you will have to dig in the logs to see what is the problem.

The FilterFile and Vacations file are checked for changes every ReportEverySecs in order to update the filters and vacations without restarting the script.

Happy log tailing!
