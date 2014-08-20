# Script name:   	check_ms_win_tasks.ps1
# Version:			2.14.08.20
# Created on:    	01/02/2014																			
# Author:        	D'Haese Willem
# Purpose:       	Checks Microsoft Windows scheduled tasks excluding defined folders and defined 
#					task patterns, returning state of tasks with name, author, exit code and 
#					performance data to Nagios.
# On Github:		https://github.com/willemdh/check_ms_win_tasks.ps1
# To do:			
#  	- Add switches to change returned values and output
#  	- Add array parameter with exit codes that should be excluded
#	- Test remote execution
# History:       	
#	03/02/2014 => Add array as argument with excluded folders
#	15/02/2014 => Add array as argument with excluded task patterns
#	03/03/2014 => Added perfdata and edited output
#	09/03/2014 => Added running tasks information and perfdata
#	22/03/2014 => Resolved a bug with output treated as perfdata
#	23/03/2014 => Created repository on Github and updated documentation
#	11/04/2014 => New output format with outputstring to be able to see failed tasks in service history
#	11/04/2014 => Added [int] to prevent decimal numbers
#	24/04/2014 => After testing multiple possibilities with `r`n and <br>, decided to not go multiline at all and used ' -> ' to split failed and running tasks
# 	05/05/2014 => Test script fro better handling and checking of parameters, does not work yet...
#	18/08/2014 => Made parameters non mandatory, working with TaskStruct object and default values, argument handling
#	20/08/2014 => Solved bugs with -h or --help not displaying help and cleaned up some code
# How to:
#	1) Put the script in the NSCP scripts folder
#	2) In the nsclient.ini configuration file, define the script like this:
#		check_ms_win_tasks=cmd /c echo scripts\check_ms_win_tasks.ps1 $ARG1$ $ARG2$ $ARG3$; exit 
#		$LastExitCode | powershell.exe -command -
#	3) Make a command in Nagios like this:
#		check_ms_win_tasks => $USER1$/check_nrpe -H $HOSTADDRESS$ -p 5666 -t 60 -c 
#		check_ms_win_tasks -a $ARG1$ $ARG2$ $ARG3$
#	4) Configure your service in Nagios:
#		- Make use of the above created command
#		- Parameter 1 should be 'localhost' (did not test with remoting)
#		- Parameter 2 should be an array of folders to exclude, example 'Microsoft, Backup'
#		- Parameter 3 should be an array of task patterns to exclude, example 'Jeff,"Copy Test"'
#		- All single quotes need to be included (In Nagios XI)
#		- Array values with spaces need double quotes (see above example)
#		- Parameters are no longer mandatory. If not used, default values in TaskStruct will be used.
# Help:
#	This script works perfectly in our environment on Windows 2008 and Windows 2008 R2 servers. If
#	you do happen to find an issue, create an issue on GitHub. The script is highly adaptable if you 
#	want different output etc. I've been asked a few times to make it multilingual, as obviously
#	this script will only work on English Windows 2008 or higher servers, but as I do not have 
#	non-English servers at my disposal, I'm not going to implement any other languages..
# Copyright:
#	This program is free software: you can redistribute it and/or modify it under the terms of the
# 	GNU General Public License as published by the Free Software Foundation, either version 3 of 
#   the License, or (at your option) any later version.
#   This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
#	without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
# 	See the GNU General Public License for more details.You should have received a copy of the GNU
#   General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

#Requires –Version 2.0

# Default values

[String]$DefaultString = "ABCD123"
[Int]$DefaultInt = -99

# Passing Structure

$TaskStruct = @{}
    [string]$TaskStruct.Hostname = "localhost"
    [string[]]$TaskStruct.ExclFolders = @()
    [string[]]$TaskStruct.ExclTasks = @()
	[string]$TaskStruct.FolderRef = ""
	[string[]]$TaskStruct.AllValidFolders = @()
    [int]$TaskStruct.Time = "1"
    [int]$TaskStruct.ExitCode = 3
	[int]$TaskStruct.UnkArgCount = 0
	[int]$TaskStruct.KnownArgCount = 0
	[int]$TaskStruct.TasksOk = 0
	[int]$TaskStruct.TasksNotOk = 0
	[int]$TaskStruct.TasksRunning = 0
	[int]$TaskStruct.TasksTotal = 0
    [String]$TaskStruct.OutputString = "Critical: There was an error processing performance counter data"
    [String]$TaskStruct.OkString = $DefaultString
    [String]$TaskStruct.WarnString = $DefaultString
    [String]$TaskStruct.CritString = $DefaultString
    [Int]$TaskStruct.WarnHigh = $DefaultInt
    [Int]$TaskStruct.CritHigh = $DefaultInt
    [Int]$TaskStruct.WarnLow = $DefaultInt
    [Int]$TaskStruct.CritLow = $DefaultInt
    $TaskStruct.Result 
	
	
	
#region Functions

Function Process-Args {
    Param ( 
        [Parameter(Mandatory=$True)]$Args,
        [Parameter(Mandatory=$True)]$Return
    )
	
# Loop through all passed arguments

    For ( $i = 0; $i -lt $Args.count-1; $i++ ) {     
        $CurrentArg = $Args[$i].ToString()
        $Value = $Args[$i+1]
        If (($CurrentArg -cmatch "-H") -or ($CurrentArg -match "--Hostname")) {
            If (Check-Strings $Value) {
                $Return.Hostname = $Value  
				$Return.KnownArgCount+=1
            }
        }
        ElseIf (($CurrentArg -cmatch "-EF") -or ($CurrentArg -match "--Excl-Folders")) {
			If ($Value.Count -ge 2) {
				$ItemCount=0
				foreach ($Item in $Value) {
            		If (Check-Strings $Item) {
                		$ItemCount+=1
            		}
				}
			}
			elseIf (Check-Strings $Value) {
                $Return.ExclFolders = $Value
				$Return.KnownArgCount+=1
			}	
			if ($ItemCount -eq $Value.count) {
				$Return.ExclFolders = $Value
				$Return.KnownArgCount+=1
			}
        }
        ElseIf (($CurrentArg -cmatch "-ET") -or ($CurrentArg -match "--Excl-Tasks")) {
            If ($Value.Count -ge 2) {
				$ItemCount=0
				foreach ($Item in $Value) {
            		If (Check-Strings $Item) {
                		$ItemCount+=1
            		}
				}
			}
			elseIf (Check-Strings $Value) {
                $Return.Excltasks = $Value  
				$Return.KnownArgCount+=1
			}	
			if ($ItemCount -eq $Value.count) {
				$Return.ExclTasks = $Value
				$Return.KnownArgCount+=1
			}
        }
        ElseIf (($CurrentArg -match "--help") -or ($CurrentArg -cmatch "-h")) { 
			$Return.KnownArgCount+=1
			Write-Help
			Exit $Return.ExitCode
		}				
       	else {
			$Return.UnkArgCount+=1
		}
    }		
	$ArgHelp = $Args[0].ToString()	
	if (($ArgHelp -match "--help") -or ($ArgHelp -cmatch "-h") ) {
		Write-Help 
		Exit $Return.ExitCode
	}	
	if ($Return.UnkArgCount -ge $Return.KnownArgCount) {
		Write-Host "Unknown: Illegal arguments detected!"
        Exit $Return.ExitCode
	}
    Return $Return
}

# Function to check strings for invalid and potentially malicious chars

Function Check-Strings {
    Param ( [Parameter(Mandatory=$True)][string]$String )
    # `, `n, |, ; are bad, I think we can leave {}, @, and $ at this point.
    $BadChars=@("``", "|", ";", "`n")

    $BadChars | ForEach-Object {

        If ( $String.Contains("$_") ) {
            Write-Host "Unknown: String contains illegal characters."
            Exit $TaskStruct.ExitCode
        }
    }
    Return $true
} 

# Function to get all task subfolders

function Get-AllTaskSubFolders {
    param (
	   [Parameter(Mandatory=$True)]$TaskStruct
    )
    if ($RootFolder) {
        $TaskStruct.AllValidFolders+=$TaskStruct.FolderRef
		return $TaskStruct
    } 
	else {
        $TaskStruct.AllValidFolders+=$TaskStruct.FolderRef	     
        if(($folders = $TaskStruct.FolderRef.getfolders(1)).count -ge 1) {
            foreach ($folder in $folders) {
				if ($TaskStruct.ExclFolders -notcontains $folder.Name) {     
                	if(($folder.getfolders(1).count -ge 1)) {
						$TaskStruct.FolderRef=$folder
                    	$TaskStruct=Get-AllTaskSubFolders $TaskStruct
                	}
					else {
							$TaskStruct.AllValidFolders+=$folder
					}					
					
				}
			}
			return $TaskStruct
        }
			
    }
	return $TaskStruct
}

# Function to check a string for patterns

function Check-Array ([string]$str, [string[]]$patterns) {
    foreach($pattern in $patterns) { if($str -match $pattern) { return $true; } }
    return $false;
}

# Function to write help output

Function Write-Help {
    Write-Host "check_ms_win_tasks.ps1:`n`tThis script is designed to check Windows 2008 or higher scheduled tasks and alert in case tasks failed in Nagios style output."
    Write-Host "Arguments:"
    Write-Host "`t-H or --Hostname ) Optional hostname of remote system, default is localhost, not yet tested on remote host."
    Write-Host "`t-EF or --Excl-Folders) Name of folders to exclude from monitoring."
    Write-Host "`t-ET or --Excl-Tasks) Name of task patterns to exclude from monitoring."
    Write-Host "`t-w or --Warning ) Warning threshold for number of failed tasks, not yet implemented."
    Write-Host "`t-c or --Critial ) Critical threshold for number of failed tasks, not yet implemented."
    Write-Host "`t-h or --Help ) Print this help output."
} 

#endregion Functions

# Main function to kick off functionality

Function Check-MS-Win-Tasks {
 	Param ( 
        [Parameter(Mandatory=$True)]$TaskStruct
     )	 
	# Try connecting to schedule service COM object
	try {
		$schedule = new-object -com("Schedule.Service") 
	} 
	catch {
		Write-Host "Schedule.Service COM Object not found, this script requires this object"
		Exit $TaskStruct.ExitCode
	} 
	$Schedule.connect($TaskStruct.hostname) 
	$TaskStruct.FolderRef = $Schedule.getfolder("\")
	$TaskStruct = Get-AllTaskSubFolders $TaskStruct
	
	[int]$TaskStruct.TasksOk = 0
	[int]$TaskStruct.TasksNotOk = 0
	[int]$TaskStruct.TasksRunning = 0
	[int]$TaskStruct.TasksTotal = 0
	
	$BadTasks = @()
	$GoodTasks = @()
	$RunningTasks = @()
	$OutputString = ""

	foreach ($Folder in $TaskStruct.AllValidFolders) {		
			    if (($Tasks = $Folder.GetTasks(0))) {
			        $Tasks | Foreach-Object {$ObjTask = New-Object -TypeName PSCustomObject -Property @{
				            'Name' = $_.name
			                'Path' = $_.path
			                'State' = $_.state
			                'Enabled' = $_.enabled
			                'LastRunTime' = $_.lastruntime
			                'LastTaskResult' = $_.lasttaskresult
			                'NumberOfMissedRuns' = $_.numberofmissedruns
			                'NextRunTime' = $_.nextruntime
			                'Author' =  ([xml]$_.xml).Task.RegistrationInfo.Author
			                'UserId' = ([xml]$_.xml).Task.Principals.Principal.UserID
			                'Description' = ([xml]$_.xml).Task.RegistrationInfo.Description
							'Cmd' = ([xml]$_.xml).Task.Actions.Exec.Command 
							'Params' = ([xml]$_.xml).Task.Actions.Exec.Arguments
			            }
					if ($ObjTask.LastTaskResult -eq "0") {
						if(!(Check-Array $ObjTask.Name $TaskStruct.ExclTasks)){
							$GoodTasks += $ObjTask
							$TaskStruct.TasksOk += 1
							}
						}
					elseif ($ObjTask.LastTaskResult -eq "0x00041301") {
						if(!(Check-Array $ObjTask.Name $TaskStruct.ExclTasks)){
							$RunningTasks += $ObjTask
							$TaskStruct.TasksRunning += 1
							}
						}
					else {
						if(!(Check-Array $ObjTask.Name $TaskStruct.ExclTasks)){
							$BadTasks += $ObjTask
							$TaskStruct.TasksNotOk += 1
							}
						}
					}
			    }	
	} 
	$TaskStruct.TasksTotal = $TaskStruct.TasksOk + $TaskStruct.TasksNotOk + $TaskStruct.TasksRunning
	if ($TaskStruct.TasksNotOk -gt "0") {
		$OutputString += "$($TaskStruct.TasksNotOk) / $($TaskStruct.TasksTotal) tasks failed! Check tasks: "
		foreach ($BadTask in $BadTasks) {
			$OutputString += " -> Task $($BadTask.Name) by $($BadTask.Author) failed with exitcode $($BadTask.lasttaskresult) "
		}
		foreach ($RunningTask in $RunningTasks) {
			$OutputString += " -> Task $($RunningTask.Name) by $($RunningTask.Author), exitcode $($RunningTask.lasttaskresult) is still running! "
		}
		$OutputString +=  " | 'Total Tasks'=$($TaskStruct.TasksTotal), 'OK Tasks'=$($TaskStruct.TasksOk), 'Failed Tasks'=$($TaskStruct.TasksNotOk), 'Running Tasks'=$($TaskStruct.TasksRunning)"
		
		$TaskStruct.ExitCode = 2
	}	
	else {
		$OutputString +=  "All $($TaskStruct.TasksTotal) tasks ran succesfully! "
		foreach ($RunningTask in $RunningTasks) {
			$OutputString +=  " -> Task $($RunningTask.Name) by $($RunningTask.Author), exitcode $($RunningTask.lasttaskresult) is still running! "
		}
		$OutputString +=  " | 'Total Tasks'=$($TaskStruct.TasksTotal), 'OK Tasks'=$($TaskStruct.TasksOk), 'Failed Tasks'=$($TaskStruct.TasksNotOk), 'Running Tasks'=$($TaskStruct.TasksRunning)"
		$TaskStruct.ExitCode = 0
	}
	Write-Host "$outputString"
	exit $TaskStruct.ExitCode
}

# Main block

# Reuse threads
if ($PSVersionTable){$Host.Runspace.ThreadOptions = 'ReuseThread'}

# Main function
if($Args.count -ge 0){$TaskStruct = Process-Args $Args $TaskStruct}
	
Check-MS-Win-Tasks $TaskStruct