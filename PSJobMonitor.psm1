using namespace System.Management.Automation
using namespace System.Windows
using namespace System.Windows.Forms
using namespace PresentationFramework
using namespace PresentationCore
using namespace System.Drawing

function Show-PSJobMonitor {
    [CmdletBinding()]
    param ()

    if ($PSBoundParameters['Debug']) {
        $DebugPreference = 'Continue'
    }

    Write-Verbose 'Adding types'
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    Write-Verbose 'Types added successfully'

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

    function Remove-JobListItem {
        param (
            [Parameter(Mandatory)]
            [Job[]]$Job
        )

        $Job | ForEach-Object {
            $Index = $ListBox_JobList.Items.IndexOf($_.Name)
            if ($Index -ge 0) {
                $ListBox_JobList.Items.RemoveAt($Index)
            }
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

        Remove-JobListItem -Job $Job
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
    }

    function Update-JobProperties {
        if ($IsJobSelected) {
            Write-Verbose ('Updating properties for: {0}'   -f $SelectedJobObject | Out-String)
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
        } else {
            Write-Verbose "No job is selected"
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
        $script:Jobs = Get-Job | Where-Object PSJobTypeName -ne $null

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

    function Register-JobEvents {
        $script:JobEventSubscriptions = @()
        $Jobs = Get-Job | Where-Object PSJobTypeName -ne $null
        foreach ($Job in $Jobs) {
            $subscription = Register-ObjectEvent -InputObject $Job -EventName StateChanged -Action {
                if ($script:SelectedJobName -eq $Job.Name) {
                    $script:SelectedJobObject = $Job
                    Update-JobOutput
                    Update-JobProperties
                    Update-ListBoxItem
                }
            }
            $script:JobEventSubscriptions += $subscription
            Write-Verbose "Registered event for job: $($Job.Name)"
        }

    }

    function Unregister-JobEvents {
        if ($script:JobEventSubscriptions) {
            foreach ($subscription in $script:JobEventSubscriptions) {
                Remove-Job -Id $subscription.Id -Force
            }
            $script:JobEventSubscriptions = @()
        }
        Update-ListBoxItem
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

    #Event Handlers
    $ListBox_JobList.Add_SelectionChanged({
        $SelectedJob = $ListBox_JobList.SelectedItem
        if ($SelectedJob) {
            $Job = Get-Job -Name $SelectedJob
            if ($Job) {
                $TextBox_JobOutput.Text = $Job.Output
            }
        }
        $IsJobSelected = $true
    })

    $ListBox_JobList.Add_SelectionChanged({
        Write-Verbose "ListBox_JobList.Add_SelectionChanged: Selected Job Name: $SelectedJobName"
        $script:SelectedJobName = $ListBox_JobList.SelectedItem
        $script:SelectedJobObject = Get-Job -Name $script:SelectedJobName
        Write-Verbose "ListBox_JobList.Add_SelectionChanged: Selected Job Object: $($SelectedJobObject | Out-String)"
        $script:IsJobSelected = $true
        Update-JobOutput
        Update-JobProperties
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
            Remove-JobListItem -Job $SelectedJobObject
        }
    })

    $ContextMenu_MenuItem_SaveLog.Add_Click({
        Export-JobLog -Job $SelectedJobObject
    })

    $Form.Add_Loaded({
        Update-JobList
        Update-ListBoxItem
        Register-JobEvents
    })

    $Form.Add_Closed({
        Unregister-JobEvents
    })

    $Form.ShowDialog() | Out-Null

    $Form.Close()

}

Export-ModuleMember -Function Show-PSJobMonitor