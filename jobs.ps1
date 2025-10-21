"Creating test jobs"
Start-ThreadJob -Name MyRunningJob -ScriptBlock {$i = 0; while ($true) {"This is MyRunningJob: {0}" -f $i; Start-Sleep -Seconds 10; $i++} }
Start-ThreadJob -Name MyCompletedJob -ScriptBlock {echo 'This is a finished job' }
Start-ThreadJob -ScriptBlock { $i = 0; while ($true) {"This is a job with no Name: {0}" -f $i; Start-Sleep -Seconds 10; $i++ } }
#Start-ThreadJob -Name MyFailedJob -ScriptBlock {'This is a failed job'; exit 1 }
Start-ThreadJob -Name MyFailedJob2 -ScriptBlock {'This is a failed job'; throw 'This is a failed job' }
Start-ThreadJob -Name Failed -ScriptBlock {this is not a valid command}

# add a job that will fail after 15 seconds of starting
Start-ThreadJob -Name FailAfter15Seconds -ScriptBlock {Start-Sleep -Seconds 15; throw 'This is a failed job' }