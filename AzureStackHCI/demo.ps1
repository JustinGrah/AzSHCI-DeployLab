$diagnosticBuffer = @()
$diagnosticChecks = 0

function Register-DiagnosticCheck() {
    Write-Host 'Registered diag check'
    $script:diagnosticChecks += 1
    Write-Host $diagnosticChecks
}

function Unregister-DiagnosticCheck() {

    Write-Host 'Unregistered diag check'
    $script:diagnosticChecks -= 1
    Write-Host $diagnosticChecks
}

function Start-Diagnostic() {
    Register-DiagnosticCheck
    $one = Start-Job -ScriptBlock {
        return Test-One
    } -InitializationScript $diagnostic

    Register-DiagnosticCheck
    $two = Start-Job -ScriptBlock {
        return Test-Two
    } -InitializationScript $diagnostic

    Register-DiagnosticCheck
    $three = Start-Job -ScriptBlock {
        return Test-Three
    } -InitializationScript $diagnostic

    Reconcile-Jobs -jobs @($one, $two, $three)
}

function Reconcile-Jobs() {
    param(
        [array] $jobs
    )

    Write-Host "In Reconciler"

    do {
        Write-Host $diagnosticChecks
        foreach($job in $jobs) {
            
            if($null -ne $job) {
                if($job.State -ne 'Running') {
    
                    switch ($job.State) {
                        'Failed' { Write-Host 'Failed Job' }
                        'Completed' {Write-Host 'Successful JOB'}
                        Default {Write-Host 'Discovered finished job'}
                    }
    
                    Unregister-DiagnosticCheck
                    $index = $jobs.IndexOf($job)
                    $jobs.SetValue($null, $index)
    
                    Receive-DiagnosticCheck -obj (Receive-Job -Job $job)
    
                } else {
                    Start-Sleep -Milliseconds 200
                }
            }
        }
    } while($diagnosticChecks -gt 0)
}

$diagnostic = {
    function Test-One {
        Start-Sleep -Seconds 5
        return @{
            'check' = 'One'
            'result' = 'One-OK'
        }
    }

    function Test-Two{
        Start-Sleep -Seconds 3
        return @{
            'check' = 'Two'
            'result' = 'Two-OK'
        }
    }
        
    function Test-Three {
        Start-Sleep -Seconds 6
        return @{
            'check' = 'Three'
            'result' = 'Three-OK'
        }
    }
}
    

function Receive-DiagnosticCheck() {
    param(
        [hashtable] $obj
    )

    Write-Host 'Received Callback'
    $script:diagnosticBuffer += $obj

    if($diagnosticChecks -le 0) {
        Write-Host 'All Checks received'
        Publish-DiagnosticChecks
    }
}

function Publish-DiagnosticChecks() {
    $diagnosticBuffer | Write-Output
}



Start-Diagnostic