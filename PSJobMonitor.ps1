using namespace System.Windows

function Update-JobProperties {
    $SelectedJob = $ListBox_JobList.SelectedItem
    if ($SelectedJob) {
        if ($SelectedJob.State -ne 'Running') {
            $Timer.Stop()
        }
        $Job = Get-Job -Name $SelectedJob
        $Label_JobName.Content          = 'Name: {0}' -f $Job.Name
        $Label_JobId.Content            = 'Id: {0}' -f $Job.Id
        $Label_JobState.Content         = 'State: {0}' -f $Job.JobStateInfo.State
        #$Label_JobStatusMessage.Content = 'Status Message: {0}' -f $Job.StatusMessage
        $Label_JobStartTime.Content     = 'Start Time: {0}' -f $Job.PSBeginTime
        $Label_JobEndTime.Content       = 'End Time: {0}' -f $Job.PSEndTime
        $Label_JobLocation.Content      = 'Location: {0}' -f $Job.Location
        $TextBox_JobCommand.Text        = $Job.Command

        if ($Job.State -eq 'Failed') {
            $Label_JobState.Foreground = [System.Windows.Media.Brushes]::Red
        } else {
            $Label_JobState.Foreground = [System.Windows.Media.Brushes]::Black
        }
    }
}

function Update-ListBoxItem {
    param (
        [System.Management.Automation.Job]$Job
    )
    # get the index of the $Job in the listbox
    $Index = $ListBox_JobList.Items.IndexOf($Job.Name)

    if ($Index -ge 0) {
        # Force the ListBox to generate its items
        $ListBox_JobList.UpdateLayout()
        # Retrieve the ListBoxItem object
        $ListBoxItem = $ListBox_JobList.ItemContainerGenerator.ContainerFromIndex($Index)

        if ($null -ne $ListBoxItem) {
            # Colorize each item in the list based on the job state
            switch ($Job.State) {
                'Running' {
                    $ListBoxItem.Foreground = [System.Windows.Media.Brushes]::Black
                }
                'Completed' {
                    $ListBoxItem.Foreground = [System.Windows.Media.Brushes]::Green
                }
                'Failed' {
                    $ListBoxItem.Foreground = [System.Windows.Media.Brushes]::Red
                }
                'Stopped' {
                    $ListBoxItem.Foreground = [System.Windows.Media.Brushes]::Gray
                }
                'Suspended' {
                    $ListBoxItem.Foreground = [System.Windows.Media.Brushes]::Yellow
                }
                default {
                    $ListBoxItem.Foreground = [System.Windows.Media.Brushes]::Black
                }
            }
        }
    }
}

function Update-JobList {
    if ((Get-Job).Count -eq 0) {
        $Timer.Stop()
        $ListBox_JobList.Visibility = [Visibility]::Hidden

        return
    }

    if ((Get-Job).Count -gt 0) {
        $ListBox_JobList.Visibility = [Visibility]::Visible
    }

    $ListBox_JobList.Items.Clear()
    $TextBox_JobOutput.Clear()
    Get-Job | ForEach-Object {
        $ListBox_JobList.Items.Add($_.Name)
        Update-ListBoxItem -Job $_
    }
}

function Update-JobOutput {
    $SelectedJob = $ListBox_JobList.SelectedItem
    if ($SelectedJob) {
        $TextBox_JobOutput.Text = Get-Job -Name $SelectedJob | Receive-Job -Keep | Out-String
    }
}

[xml]$Xaml = Get-Content -Raw (Join-Path $PSScriptRoot PSJobMonitor.xaml)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

[System.Windows.Forms.Application]::EnableVisualStyles() | Out-Null

try {
    $XmlNodeReader = (New-Object System.Xml.XmlNodeReader $Xaml)
    $Form = [Windows.Markup.XamlReader]::Load($XmlNodeReader)
}
catch {
    throw $_
}

$Xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object {
    Set-Variable -Name ($_.Name) -Value $Form.FindName($_.Name) -Scope Script
}

#$Window_Main.Background = [System.Windows.Media.Brushes]::Gray

#$Button_Cancel.Visibility = [Visibility]::Hidden # not working

$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 1000 # in milliseconds

# Event Handlers
$ListBox_JobList.Add_SelectionChanged({
    $SelectedJob = $ListBox_JobList.SelectedItem
    if ($SelectedJob) {
        $Timer.Start()
    }
    else {
        $Timer.Stop()
    }
})

$Timer.Add_Tick({
    Update-JobOutput
    Update-JobProperties
    Update-ListBoxItem
})

$Button_Refresh.Add_Click({
    $ListBox_JobList.Items.Clear()
    $TextBox_JobOutput.Clear()
    Get-Job | ForEach-Object {
        $ListBox_JobList.Items.Add($_.Name)
    }
})

$Button_Cancel.Add_Click({
    $SelectedJob = $ListBox_JobList.SelectedItem
    if ($SelectedJob) {
        $Job = Get-Job -Name $SelectedJob
        if ($Job) {
            $Job | Stop-Job | Remove-Job -Force
        }
    }
})

$ListBox_JobList.Add_SelectionChanged({
    $SelectedJob = $ListBox_JobList.SelectedItem
    if ($SelectedJob) {
        $Job = Get-Job -Name $SelectedJob
        if ($Job) {
            $TextBox_JobOutput.Text = $Job.Output
        }
    }
})

$Form.Add_Loaded({
    Update-JobList
})

# Show the form
$Form.ShowDialog() | Out-Null

# Cleanup
$Form.Close()
