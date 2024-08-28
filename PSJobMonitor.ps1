
using namespace System.Management.Automation
using namespace System.Windows
using namespace System.Windows.Forms
using namespace PresentationFramework
using namespace PresentationCore
using namespace System.Drawing

[CmdletBinding()]
param ()

if ($PSBoundParameters['Debug']) {
    $XamlWatcherLib  = (Join-Path (Split-Path -Parent (Get-package XamlWatcher.WPF).Source) -ChildPath 'lib\net45\XamlWatcher.WPF.dll')
    [System.Reflection.Assembly]::LoadFrom($XamlWatcherLib)
    $XamlWatcher = New-Object XamlWatcher.WPF.Watcher($PSScriptRoot)
    $DebugPreference = 'Continue'
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

function Export-AllJobLogs {
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
}

function Export-JobLog {
    $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveFileDialog.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
    $SaveFileDialog.Title = 'Save Job Output'
    $SaveFileDialog.FileName = $SelectedJobObject.Name
    $SaveFileDialog.ShowDialog() | Out-Null

    if ($SaveFileDialog.FileName) {
        $TextBox_JobOutput.Text | Out-File -FilePath $SaveFileDialog.FileName
    }
}
function Remove-ThisJob {
    param (
        [Parameter(Mandatory)]
        [Job]$Job
    )

    $Job | Remove-Job -Force
    Update-JobList
}

function Stop-ThisJob {
    param (
        [Parameter(Mandatory)]
        [Job]$Job
    )

    if ($IsJobSelected -and $Job.State -eq 'Running') {
        $Job.StopJob()
        Update-JobList
    }
}

function Restart-Job {
    param (
        [Parameter(Mandatory)]
        [Job]$Job
    )

    if (-not $Job.PSObject.Properties['RestartCount']) {
        $Job | Add-Member -MemberType NoteProperty -Name RestartCount -Value 0
    }

    $Job.RestartCount++

    $Job | Stop-Job
    Start-ThreadJob -Name ("{0} - Retry #{1}" -f $Job.Name, $Job.RestartCount) -ScriptBlock ([ScriptBlock]::Create($Job.Command))
    $TextBox_JobOutput.Clear()
    Update-JobList
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
        $Index = $ListBox_JobList.Items.IndexOf($_.Name)

        if ($Index -ge 0) {
            $ListBox_JobList.UpdateLayout()
            $ListBoxItem = $ListBox_JobList.ItemContainerGenerator.ContainerFromIndex($Index)

            if ($null -ne $ListBoxItem) {
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
        $TextBox_JobOutput.Text = $SelectedJobObject | Receive-Job -Keep | Out-String -Stream # Do we need -Stream?
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

$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 1000 # in milliseconds

# Event Handlers
$ListBox_JobList.Add_SelectionChanged({
    $script:SelectedJobName = $ListBox_JobList.SelectedItem

    #$Timer.Start()
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
    Stop-ThisJob -Job $SelectedJobObject
})

$MenuItem_RemoveJob.Add_Click({
    Remove-Job -Job $SelectedJobObject
})

$MenuItem_SaveAllLogs.Add_Click({
    Export-AllJobLogs
})

$MenuItem_SaveLog.Add_Click({
    Export-JobLog
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

$ContextMenu_MenuItem_RestartJob.Add_Click({
    Restart-Job -Job $SelectedJobObject
})

$ContextMenu_MenuItem_StopJob.Add_Click({
    Stop-ThisJob -Job $SelectedJobObject
})

$ContextMenu_MenuItem_RemoveJob.Add_Click({
    if ($IsJobSelected) {
        $SelectedJobObject | Remove-Job -Force
        Update-JobList
    }
})

$ContextMenu_MenuItem_SaveLog.Add_Click({
    Export-JobLog
})

$ContextMenu_MenuItem_SaveAllLogs.Add_Click({
    Export-AllJobLogs
})

$Form.Add_Loaded({
    Update-JobList
    $Timer.Start()

    if ($PSBoundParameters['Debug']) {
        $XamlWatcher.Watch()
    }
})

$Form.ShowDialog() | Out-Null

$Form.Close()
