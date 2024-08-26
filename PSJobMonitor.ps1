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

    if ($SelectedJobName) {
        $Timer.Start()
    } else {
        $Timer.Stop()
    }
})

$Timer.Add_Tick({
    $script:IsJobSelected = $ListBox_JobList.SelectedItem -ne $null
    $Button_Cancel.IsEnabled = $IsJobSelected

    if ($IsJobSelected) {
        $script:SelectedJobObject = Get-Job -Name $SelectedJobName
        Update-JobProperties
        Update-JobOutput
    }

    Update-ListBoxItem
})

# $Button_Refresh.Add_Click({
#     $ListBox_JobList.Items.Clear()
#     $TextBox_JobOutput.Clear()
#     Get-Job | ForEach-Object {
#         $ListBox_JobList.Items.Add($_.Name)
#     }
# })

$Button_Cancel.Add_Click({
    if ($IsJobSelected) {
        $SelectedJobObject.Name | Stop-Job -PassThru | Remove-Job -Force
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
