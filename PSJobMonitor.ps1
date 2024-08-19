using namespace System.Windows

function Update-JobProperties {
    $SelectedJob = $ListBox_JobList.SelectedItem
    if ($SelectedJob) {
        $Job = Get-Job -Name $SelectedJob
        $Label_JobName.Content          = 'Name: {0}' -f $Job.Name
        $Label_JobId.Content            = 'Id: {0}' -f $Job.Id
        $Label_JobState.Content         = 'State: {0}' -f $Job.JobStateInfo.State
        #$Label_JobStatusMessage.Content = 'Status Message: {0}' -f $Job.StatusMessage
        $Label_JobStartTime.Content     = 'Start Time: {0}' -f $Job.PSBeginTime
        $Label_JobEndTime.Content       = 'End Time: {0}' -f $Job.PSEndTime
        $Label_JobLocation.Content      = 'Location: {0}' -f $Job.Location
        $TextBox_JobCommand.Text        = $Job.Command
    }
}

function Update-JobList {
    # Refresh the list of jobs
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
    }
}

function Update-JobOutput {
    # Display the output of the selected job
    $SelectedJob = $ListBox_JobList.SelectedItem
    if ($SelectedJob) {
        $TextBox_JobOutput.Text = Get-Job -Name $SelectedJob | Receive-Job -Keep
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

$Button_Cancel.Visibility = [Visibility]::Hidden # not working

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
