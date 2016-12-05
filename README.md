# 9to5tail

A simple perl based script that will spam you with logs. It will actually tail -f your log, ignore the silly things that you don't care about using perl regex specified in FilterFile (like running "egrep -v -f Filterfile DataFile") and will send you an mail every ReportEverySecs with the important stuff during working hours.

Configuration is specified in yaml format (see testlog.yml). You may specify multiple recipients, one log file and one filter file per instance.

Non working time is defined in sub "isNowWorkTime", return 0 for non working time. Adjust as needed.

eg #1:

return 0 if ( ( $now->hour() < 9) || ( $now->hour() >= 18 ) || ( ( $now->hour() == 18) && ( $now->min() >= 30) ) ); 

defines that mails will not be sent between 18:30 - 09:00

eg #2
return 0 if ( $now->day_of_week == 6 || $now->day_of_week == 7 );

defines that emails will not be sent during weekends

in Vacations file you may specify the vacation days of the recipients so that they don't get spammed while relaxing, in the format :
email, year, month, day

Thanks to File::Tail, you don't have to restart when the log file is rotated

kill -SIGUSR1  will dump in the script's log file (TailerLog) the counters for ignored lines, allowing you to optimize the order of the filters and gain some speed.

kill -SIGTERM will gracefully terminate the process, sending any pending reports.

MaxReportBytes defines the maximum size of the report mail. Report will be truncated to get an idea of what is happening but you will have to dig in the logs to see what is the problem.

The FilterFile and Vacations file are checked for changes every ReportEverySecs in order to update the filters and vacations without restarting the script.




