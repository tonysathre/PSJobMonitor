using namespace System.Management.Automation
using namespace System.Windows
using namespace System.Windows.Forms
using namespace PresentationFramework
using namespace PresentationCore
using namespace System.Drawing

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms


function Restart-Job {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Job]$Job
    )

    if ($IsJobSelected) {
        $Job | Stop-Job
        Start-ThreadJob -Name "$($SelectedJobObject.Name) - Restart" -ScriptBlock ([ScriptBlock]::Create($SelectedJobObject.Command))
        $TextBox_JobOutput.Clear()
        Update-JobList
    }
}
function Update-JobProperties {
    if ($IsJobSelected) {
        #if ($SelectedJobObject.State -ne 'Running') {
        #    $Timer.Stop()
        #}
        $Label_JobName.Content      = 'Name: {0}'       -f $SelectedJobObject.Name
        $Label_JobId.Content        = 'Id: {0}'         -f $SelectedJobObject.Id
        $Label_JobState.Content     = 'State: {0}'      -f $SelectedJobObject.JobStateInfo.State
        $Label_JobStartTime.Content = 'Start Time: {0}' -f $SelectedJobObject.PSBeginTime
        $Label_JobEndTime.Content   = 'End Time: {0}'   -f $SelectedJobObject.PSEndTime
        $Label_JobLocation.Content  = 'Location: {0}'   -f $SelectedJobObject.Location
        $TextBox_JobCommand.Text    = $SelectedJobObject.Command

        if ($SelectedJobObject.State -eq 'Failed') {
            $Label_JobState.Foreground = [System.Windows.Media.Brushes]::Red
        } else {
            $Label_JobState.Foreground = [System.Windows.Media.Brushes]::Black
        }
    }
}

function Update-ListBoxItem {
    $Jobs | ForEach-Object {
        # get the index of the $Job in the listbox
        $Index = $ListBox_JobList.Items.IndexOf($_.Name)

        if ($Index -ge 0) {
            # Force the ListBox to generate its items
            $ListBox_JobList.UpdateLayout()
            # Retrieve the ListBoxItem object
            $ListBoxItem = $ListBox_JobList.ItemContainerGenerator.ContainerFromIndex($Index)

            if ($null -ne $ListBoxItem) {
                # Colorize each item in the list based on the job state
                switch ($_.State) {
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
}

function Update-JobList {
    $script:Jobs = Get-Job
    if ($Jobs.Count -eq 0) {
        $Timer.Stop()
        $ListBox_JobList.Visibility = [Visibility]::Hidden

        return
    }

    if ($Jobs.Count -gt 0) {
        $ListBox_JobList.Visibility = [Visibility]::Visible
    }

    $ListBox_JobList.Items.Clear()
    $TextBox_JobOutput.Clear()
    $Jobs | ForEach-Object {
        $ListBox_JobList.Items.Add($_.Name)
    }
}

function Update-JobOutput {
    if ($IsJobSelected) {
        $TextBox_JobOutput.Text = $SelectedJobObject | Receive-Job -Keep | Out-String -Stream
    }
}

[xml]$Xaml = Get-Content -Raw (Join-Path $PSScriptRoot PSJobMonitor.xaml)

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
$Button_Cancel.IsEnabled = $false # disable the cancel button until a job is selected
$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 1000 # in milliseconds

# Event Handlers
$ListBox_JobList.Add_SelectionChanged({
    $script:SelectedJobName = $ListBox_JobList.SelectedItem

    $Timer.Start()
})

$Timer.Add_Tick({
    $script:IsJobSelected = $ListBox_JobList.SelectedItem -ne $null

    if ($IsJobSelected) {
        $script:SelectedJobObject = Get-Job -Name $SelectedJobName
        Update-JobProperties
        Update-JobOutput
    }

    Update-ListBoxItem
})

$MenuItem_Exit.Add_Click({
    $Form.Close()
})

$MenuItem_RestartJob.Add_Click({
    Restart-Job -Job $SelectedJobObject
})

$MenuItem_StopJob.Add_Click({
    if ($IsJobSelected -and $SelectedJobObject.State -eq 'Running') {
        $SelectedJobObject.StopJob()
        Update-JobList
    }
})

$MenuItem_RemoveJob.Add_Click({
    if ($IsJobSelected) {
        $SelectedJobObject | Remove-Job -Force
        Update-JobList
    }
})

$MenuItem_SaveAllLogs.Add_Click({
    $FolderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderBrowserDialog.Description = 'Select a folder to save the job logs'
    $FolderBrowserDialog.ShowDialog() | Out-Null

    if ($FolderBrowserDialog.SelectedPath) {
        $Jobs | ForEach-Object {
            $JobName = $_.Name
            $LogFilePath = Join-Path $FolderBrowserDialog.SelectedPath "$JobName.log"
            $_ | Receive-Job -Keep | Out-File -FilePath $LogFilePath
        }
    }
})

$MenuItem_SaveLog.Add_Click({
    $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveFileDialog.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
    $SaveFileDialog.Title = 'Save Job Output'
    $SaveFileDialog.ShowDialog() | Out-Null

    if ($SaveFileDialog.FileName) {
        $TextBox_JobOutput.Text | Out-File -FilePath $SaveFileDialog.FileName
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
    $Timer.Start()
})

$Form.ShowDialog() | Out-Null

$Form.Close()
