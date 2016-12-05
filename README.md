# 9to5tail
A perl based script that will tail -f your log, ignore the silly things specified using regex in FilterFile (like running egrep -v -f DataFile) and send you an mail every ReportEverySecs with the important stuff during working hours.

Work time is defined in "isNowWorkTime". Adjust as needed.
eg #1:
return 0 if ( ( $now->hour() < 9) || ( ( $now->hour() >= 18) && ( $now->min() >= 30) ) || ( $now->hour() >= 18 ) ); 
defines that mails will not be sent between 18:30 - 09:00

eg #2
return 0 if ( $now->day_of_week == 6 || $now->day_of_week == 7 );
defines that mails will not be send in during weekends

Thanks to File::Tail, you don't have to restart when the log file is rotated

kill -SIGUSR1  will dump in the script's log file (TailerLog) the counters for ignored lines, allowing you to optimize the order of the filters and gain some speed.
kill -SIGTERM will gracefully terminate the process, sending any pending reports.more 

in Vacations file you can specify the vacation days of the recipients so that they don't get spammed while relaxing, in the format :
email, year, month, day

MaxReportBytes defines the maximum size of the report mail. Report will be truncated to get an idea of what is happening but you will have to dig manually the logs.

The FilterFile and Vacations file are checked for changes every ReportEverySecs in order to update the filters and vacations without restarting the script.




