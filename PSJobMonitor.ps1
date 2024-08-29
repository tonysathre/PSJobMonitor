
using namespace System.Management.Automation
using namespace System.Windows
using namespace System.Windows.Forms
using namespace PresentationFramework
using namespace PresentationCore
using namespace System.Drawing

[CmdletBinding()]
param ()

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

function Export-JobLog {
    param (
        [Parameter(Mandatory)]
        [Job[]]$Job
    )

    if ($Job.Count -eq 1) {
        $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $SaveDialog.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
        $SaveDialog.FileName = $Job.Name
        $SaveDialog.Title = 'Save Job Output'
        $DialogResult = $SaveDialog.ShowDialog()

        if ($DialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }

        $Job.Output | Out-File -FilePath $SaveDialog.FileName

        return
    }

    $FolderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderDialog.Description = 'Select a folder to save the job logs'
    $DialogResult = $FolderDialog.ShowDialog()

    if ($DialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    $Job | ForEach-Object {
        $_.Output | Out-File -FilePath (Join-Path $FolderDialog.SelectedPath "$($_.Name).txt")
    }
}

function Remove-ThisJob {
    param (
        [Parameter(Mandatory)]
        [Job[]]$Job
    )

    $Job | ForEach-Object {
        $_ | Remove-Job -Force
    }

    Update-JobList
}

function Stop-ThisJob {
    param (
        [Parameter(Mandatory)]
        [Job[]]$Job
    )

    $Job | ForEach-Object {
        if ($_.State -eq 'Running') {
            $_.StopJob()
        }
    }

    Update-JobList
}

function Restart-Job {
    param (
        [Parameter(Mandatory)]
        [Job[]]$Job
    )

    $Job | ForEach-Object {
        if (-not $_.PSObject.Properties['RestartCount']) {
            $_ | Add-Member -MemberType NoteProperty -Name RestartCount -Value 0
        }

        $_.RestartCount++

        $_ | Stop-Job
        Start-ThreadJob -Name ("{0} - Retry #{1}" -f $_.Name, $_.RestartCount) -ScriptBlock ([ScriptBlock]::Create($_.Command))
        $TextBox_JobOutput.Clear()
    }

    Update-JobList
}

function Update-JobProperties {
    if ($IsJobSelected) {
        $Label_JobName.Content      = 'Name: {0}'       -f $SelectedJobObject[-1].Name
        $Label_JobId.Content        = 'Id: {0}'         -f $SelectedJobObject[-1].Id
        $Label_JobState.Content     = 'State: {0}'      -f $SelectedJobObject[-1].JobStateInfo.State
        $Label_JobStartTime.Content = 'Start Time: {0}' -f $SelectedJobObject[-1].PSBeginTime
        $Label_JobEndTime.Content   = 'End Time: {0}'   -f $SelectedJobObject[-1].PSEndTime
        $Label_JobLocation.Content  = 'Location: {0}'   -f $SelectedJobObject[-1].Location
        $TextBox_JobCommand.Text    = $SelectedJobObject[-1].Command

        switch ($SelectedJobObject.State) {
            'Running' {
                $Label_JobState.Foreground = [System.Windows.Media.Brushes]::Black
            }
            'Completed' {
                $Label_JobState.Foreground = [System.Windows.Media.Brushes]::Green
            }
            'Failed' {
                $Label_JobState.Foreground = [System.Windows.Media.Brushes]::Red
            }
            'Stopped' {
                $Label_JobState.Foreground = [System.Windows.Media.Brushes]::Gray
            }
            'NotStarted' {
                $Label_JobState.Foreground = [System.Windows.Media.Brushes]::Blue
            }
            default {
                $Label_JobState.Foreground = [System.Windows.Media.Brushes]::Black
            }
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
                    'NotStarted' {
                        $ListBoxItem.Foreground = [System.Windows.Media.Brushes]::Blue
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

    # Not sure if we want to hide the listbox if there are no jobs
    if ($Jobs.Count -eq 0) {
        $ListBox_JobList.Visibility = [Visibility]::Hidden

        return
    } else {
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
        $TextBox_JobOutput.Text = $SelectedJobObject[-1].Output | Out-String
        $TextBox_JobErrors.Text = $SelectedJobObject[-1].Error | Out-String
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
    $script:SelectedJobName = $ListBox_JobList.SelectedItems

    #$Timer.Start()
})

$Timer.Add_Tick({
    $script:IsJobSelected = $ListBox_JobList.SelectedItems -ne $null

    if ($IsJobSelected) {
        $script:SelectedJobObject = Get-Job -Name $SelectedJobName
        Update-JobProperties
        Update-JobOutput
    }

    Update-ListBoxItem

    if ($PSBoundParameters['Debug']) {

        Write-Debug ('Selected Items count: {0}' -f ($ListBox_JobList.SelectedItems.Count))
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
    Export-JobLog -Job $SelectedJobObject
})

$Form.Add_Loaded({
    Update-JobList
    $Timer.Start()
})

$Form.ShowDialog() | Out-Null

$Form.Close()
