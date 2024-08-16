<#
This script will be a GUI app using a XAML form to allow the user to see a list of background jobs started by Start-ThreadJob with build_all.ps1.
The user can select one of the jobs and the jobs output will be displayed in a textbox.

The layout of the XAML form should be as follows:
- A listbox to display the list of jobs on the left side of the form
- A textbox to display the output of the selected job on the right side of the form
- A button to refresh the list of jobs
- A button to cancel the selected job
- The JobOutput textbox should be read-only
- The JobOutput textbox should be multiline
- The JobOutput textbox should have a vertical scrollbar
- The JobOutput textbox should have word wrap enabled
- The JobOutput textbox should have a monospaced font
- The JobOutput should refresh in real-time as the job progresses
#>

function Update-JobList {
    # Refresh the list of jobs
    $JobList.Items.Clear()
    $JobOutput.Clear()
    Get-Job | ForEach-Object {
        $JobList.Items.Add($_.Name)
    }
}

function Update-JobOutput {
    # Display the output of the selected job
    $SelectedJob = $JobList.SelectedItem
    if ($SelectedJob) {
        $JobOutput.Text = Get-Job -Name $SelectedJob | Receive-Job -Keep
    }
}

# Load the XAML form
[xml]$Xaml = Get-Content -Raw (Join-Path $PSScriptRoot JobMonitor.xaml)

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

$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 1000 # in milliseconds

# Add event handlers
$JobList.Add_SelectionChanged({
    $SelectedJob = $JobList.SelectedItem
    if ($SelectedJob) {
        $Timer.Start()
    }
    else {
        $Timer.Stop()
    }
})

# Event handler for Timer Tick event
$Timer.Add_Tick({
    Update-JobOutput
})

$RefreshButton.Add_Click({
    # Refresh the list of jobs
    $JobList.Items.Clear()
    $JobOutput.Clear()
    Get-Job | ForEach-Object {
        $JobList.Items.Add($_.Name)
    }
})

$CancelButton.Add_Click({
    # Cancel the selected job
    $SelectedJob = $JobList.SelectedItem
    if ($SelectedJob) {
        $Job = Get-Job -Name $SelectedJob
        if ($Job) {
            $Job | Stop-Job
        }
    }
})

$JobList.Add_SelectionChanged({
    # Display the output of the selected job
    $SelectedJob = $JobList.SelectedItem
    if ($SelectedJob) {
        $Job = Get-Job -Name $SelectedJob
        if ($Job) {
            $JobOutput.Text = $Job.Output
        }
    }
})

$Form.Add_Loaded({
    # Refresh the list of jobs when the form is loaded
    Update-JobList
})

# Show the form
$Form.ShowDialog() | Out-Null

# Cleanup
$Form.Close()
