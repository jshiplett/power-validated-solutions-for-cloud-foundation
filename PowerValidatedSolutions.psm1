# PowerShell module for VMware Cloud Foundation Validated Solutions
# Contributions, Improvements &/or Complete Re-writes Welcome!
# https://github.com/?

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### Note
# This powershell module should be considered entirely experimental. It is still in development & not tested beyond lab
# scenarios. It is recommended you dont use it for any production environment without testing extensively!

# Enable communication with self signed certs when using Powershell Core. If you require all communications to be secure
# and do not wish to allow communication with self signed certs remove lines 17-38 before importing the module.

if ($PSEdition -eq 'Core') {
    $PSDefaultParameterValues.Add("Invoke-RestMethod:SkipCertificateCheck", $true)
}

if ($PSEdition -eq 'Desktop') {
    # Enable communication with self signed certs when using Windows Powershell
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

    if ("TrustAllCertificatePolicy" -as [type]) {} else {
        add-type @"
	using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertificatePolicy : ICertificatePolicy {
        public TrustAllCertificatePolicy() {}
		public bool CheckValidationResult(
            ServicePoint sPoint, X509Certificate certificate,
            WebRequest wRequest, int certificateProblem) {
            return true;
        }
	}
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertificatePolicy
    }
}

####  Do not modify anything below this line. All user variables are in the accompanying JSON files #####

Function Resolve-PSModule {
    <#
        .SYNOPSIS
        Check for a PowerShell module presence, if not there try to import/install it.

        .DESCRIPTION
        This function is not exported. The idea is to use the return searchResult from the caller function to establish
        if we can proceed to the next step where the module will be required (developed to check on Posh-SSH).
        Logic:
        - Check if module is imported into the current session
        - If module is not imported, check if available on disk and try to import
        - If module is not imported & not available on disk, try PSGallery then install and import
        - If module is not imported, not available and not in online gallery then abort

        Informing user only if the module needs importing/installing. If the module is already present nothing will be displayed.

        .EXAMPLE
        PS C:\> $poshSSH = Resolve-PSModule -moduleName "Posh-SSH"
        This example will check if the current PS module session has Posh-SSH installed, if not will try to install it
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$moduleName
    )

    # Check if module is imported into the current session
    if (Get-Module -Name $moduleName) {
        $searchResult = "ALREADY_IMPORTED"
    }
    else {
        # If module is not imported, check if available on disk and try to import
        if (Get-Module -ListAvailable | Where-Object { $_.Name -eq $moduleName }) {
            Try {
                "`n Module $moduleName not loaded, importing now please wait..."
                Import-Module $moduleName
                Write-Output "Module $moduleName imported successfully."
                $searchResult = "IMPORTED"
            }
            Catch {
                $searchResult = "IMPORT_FAILED"
            }
        }
        else {
            # If module is not imported & not available on disk, try PSGallery then install and import
            if (Find-Module -Name $moduleName | Where-Object { $_.Name -eq $moduleName }) {
                Try {
                    Write-Output "Module $moduleName was missing, installing now please wait..."
                    Install-Module -Name $moduleName -Force -Scope CurrentUser
                    Write-Output "Importing module $moduleName, please wait..."
                    Import-Module $moduleName
                    Write-Output "Module $moduleName installed and imported"
                    $searchResult = "INSTALLED_IMPORTED"
                }
                Catch {
                    $searchResult = "INSTALLIMPORT_FAILED"
                }
            }
            else {
                # If module is not imported, not available and not in online gallery then abort
                $searchResult = "NOTAVAILABLE"
            }
        }
    }
    Return $searchResult
}

#######################################################################################################################
#################  I D E N T I T Y   A N D   A C C E S S   M A N A G E M E N T   F U N C T I O N S   ##################

Function Add-IdentitySource {
    <#
		.SYNOPSIS
    	Add Active Directory over LDAP/LDAPS as an Identity Provider to vCenter Server

    	.DESCRIPTION
    	The Add-IdentitySource cmdlets adds Active Directory over LDAP/LDAPS as an Identity Provider to the vCenter
        Server and configures is as the default provider. The cmdlet connects to SDDC Manager using the -server, -user,
        and -password values to retrive the management domain vCenter server details from its inventory and then:
        - Verifies a connection to the Active Directory domain controller using the -domain and -dcMachineName values
        - Adds the Active Directory domain as an Identity Provider if not already present
        - Configures the new domain as the default Identity Provider

    	.EXAMPLE
    	Add-IdentitySource -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo.rainpole.io -domainBindUser svc-vsphere-ad -domainBindPass VMw@re1! -dcMachineName dc-sfo01 -baseGroupDn "ou=Security Groups,dc=sfo,dc=rainpole,dc=io" -baseUserDn "ou=Security Users,dc=sfo,dc=rainpole,dc=io" -protocol ldap
        This example adds the sfo.rainpole.io domain as the default Identity Provider to vCenter Server using LDAP

        .EXAMPLE
    	Add-IdentitySource -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo.rainpole.io -domainBindUser svc-vsphere-ad -domainBindPass VMw@re1! -dcMachineName dc-sfo01 -baseGroupDn "ou=Security Groups,dc=sfo,dc=rainpole,dc=io" -baseUserDn "ou=Security Users,dc=sfo,dc=rainpole,dc=io" -protocol ldaps -certificate F:\certificates\Root64.cer
        This example adds the sfo.rainpole.io domain as the default Identity Provider to vCenter Server using LDAPS
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainBindUser,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainBindPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$dcMachineName,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$baseGroupDn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$baseUserDn,
        [Parameter (Mandatory = $true)] [ValidateSet("ldap", "ldaps")] [String]$protocol,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$certificate
    )

    if (!$PsBoundParameters.ContainsKey("certificate") -and ($protocol -eq "ldaps")) {
        $certificate = Get-ExternalFileName -title "Select the Root CA Certificate File (.cer)" -fileType "cer" -location "default"
    }
    elseif ($protocol -eq "ldaps") {
        if (!(Test-Path -Path $certificate)) {
            Write-Error  "Certificate (cer) for Root Certificate Authority '$certificate' File Not Found"
            Break
        }
    }

    $domainAlias = ($domain.Split("."))[0].ToUpper()
    $bindUser = $domainBindUser + '@' + ($domain.Split("."))[0].ToLower()
    if ($protocol -eq "ldaps") {
        $primaryUrl = 'ldaps://' + $dcMachineName + '.' + $domain + ':636'
    }
    elseif ($protocol -eq "ldap") {
        $primaryUrl = 'ldap://' + $dcMachineName + '.' + $domain + ':389'
    }

    Try {
        $ssoServer = Get-vCenterServerDetail -server $server -user $user -pass $pass -domainType MANAGEMENT
        $ssoConnection = Connect-SsoAdminServer -Server $ssoServer.fqdn -User $ssoServer.ssoAdmin -Password $ssoServer.ssoAdminPass
        if ($DefaultSsoAdminServers.Name -eq $($ssoServer.fqdn)) {
            if (Get-IdentitySource -Server $ssoConnection | Where-Object { $_.Name -eq $domain }) {
                Write-Warning "Identity Source $domain already added to vCenter Server $($ssoServer.fqdn)"
            }
            else {
                if (Test-Connection -ComputerName ($dcMachineName + "." + $domain) -Quiet -Count 1) {
                    if ($protocol -eq "ldaps") {
                        Add-LDAPIdentitySource -ServerType ActiveDirectory -Name $domain -DomainName $domain -DomainAlias $domainAlias -PrimaryUrl $primaryUrl -BaseDNUsers $baseUserDn -BaseDNGroups $baseGroupDn -Username $bindUser -Password $domainBindPass -Certificate $certificate
                    }
                    else {
                        Add-LDAPIdentitySource -ServerType ActiveDirectory -Name $domain -DomainName $domain -DomainAlias $domainAlias -PrimaryUrl $primaryUrl -BaseDNUsers $baseUserDn -BaseDNGroups $baseGroupDn -Username $bindUser -Password $domainBindPass
                    }
                    if (Get-IdentitySource -Server $ssoConnection | Where-Object { $_.Name -eq $domain }) {
                        Connect-VIServer -Server $ssoServer.fqdn -User $ssoServer.ssoAdmin -Password $ssoServer.ssoAdminPass | Out-Null
                        if ($DefaultVIServer.Name -eq $($ssoServer.fqdn)) {
                            $scriptCommand = '/opt/vmware/bin/sso-config.sh -set_default_identity_sources -i ' + $domain + ''
                            $output = Invoke-VMScript -VM $ssoServer.vmName -ScriptText $scriptCommand -GuestUser $ssoServer.root -GuestPassword $ssoServer.rootPass
                        }
                        else {
                            Write-Error  "Not connected to vCenter Server $($ssoServer.fqdn)"
                        }
                    }
                    else {
                        Write-Error  "Adding Identity Source $domain to vCenter Server $($ssoServer.vmName) Failed"
                        Break
                    }
                    $scriptCommand = '/opt/vmware/bin/sso-config.sh -set_default_identity_sources -i ' + $domain + ''
                    $output = Invoke-VMScript -VM $ssoServer.vmName -ScriptText $scriptCommand -GuestUser $ssoServer.root -GuestPassword $ssoServer.rootPass
                    Write-Output  "Confirmed adding Identity Source $domain and setting as default to vCenter Server $($ssoServer.fqdn) Successfully"
                    Disconnect-VIServer -Server $ssoServer.fqdn -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                else {
                    Write-Error  "Domain Controller $dcMachineName is not contactable"
                    Break
                }
            }
            Disconnect-SsoAdminServer -Server $ssoServer.fqdn -WarningAction SilentlyContinue
        }
        else {
            Write-Error  "Not connected to Single-Sign On Domain Server $($ssoServer.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-IdentitySource

Function Add-SddcManagerRole {
    <#
		.SYNOPSIS
    	Assign SDDC Manager roles to a user/group

    	.DESCRIPTION
    	The Add-SddcManagerRole cmdlet assigns an SDDC Manager role to the user or group provided.
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values and then:
        - Verifies that the bind credetials are valid
        - Verifies that the domain is present in vCenter Server as an Identity Provider
        - Verifies the user or group exists in Active Directory
        - Assigns the user or group to the SDDC Manager role

    	.EXAMPLE
    	Add-SddcManagerRole -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo.rainpole.io -domainBindUser svc-vsphere-ad -domainBindPass VMw@re1! -principal gg-vcf-admins -role ADMIN -type group
        This example assigns the group gg-vcf-admins from domain sfo.rainpole.io the SDDC Manager role ADMIN

        .EXAMPLE
    	Add-SddcManagerRole -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo.rainpole.io -domainBindUser svc-vsphere-ad -domainBindPass VMw@re1! -principal gg-vcf-operators -role OPERATOR -type group
        This example assigns the group gg-vcf-operators from domain sfo.rainpole.io the SDDC Manager role OPERATOR

        .EXAMPLE
    	Add-SddcManagerRole -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo.rainpole.io -domainBindUser svc-vsphere-ad -domainBindPass VMw@re1! -principal gg-vcf-viewers -role VIEWER -type group
        This example assigns the group gg-vcf-viewers from domain sfo.rainpole.io the SDDC Manager role VIEWER
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainBindUser,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainBindPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$principal,
        [Parameter (Mandatory = $true)] [ValidateSet("ADMIN", "OPERATOR", "VIEWER")] [String]$role,
        [Parameter (Mandatory = $true)] [ValidateSet("group", "user")] [String]$type
    )

    Try {
        $checkAdAuthentication = Test-ADAuthentication -user $domainBindUser -pass $domainBindPass -server $domain -domain $domain -ErrorAction SilentlyContinue
        if ($checkAdAuthentication[1] -match "Authentication Successful") {
            $securePass = ConvertTo-SecureString -String $domainBindPass -AsPlainText -Force
            $domainCreds = New-Object System.Management.Automation.PSCredential ($domainBindUser, $securePass)
            Request-VCFToken -fqdn $server -Username $user -Password $pass | Out-Null
            if ($accessToken) {
                $ssoServer = Get-vCenterServerDetail -server $server -user $user -pass $pass -domainType MANAGEMENT
                $ssoConnection = Connect-SsoAdminServer -Server $ssoServer.fqdn -User $ssoServer.ssoAdmin -Password $ssoServer.ssoAdminPass
                if (Get-IdentitySource -Server $ssoConnection | Where-Object { $_.Name -eq $domain }) {
                    if ($type -eq "group") { $adObjectCheck = (Get-ADGroup -Server $domain -Credential $domainCreds -Filter { SamAccountName -eq $principal }) }
                    elseif ($type -eq "user") { $adObjectCheck = (Get-ADUser -Server $domain -Credential $domainCreds -Filter { SamAccountName -eq $principal }) }
                    if ($adObjectCheck) {
                        if ($type -eq "group") {
                            $vcfCheck = Get-VCFUser | Where-Object { $_.name -eq $($domain.ToUpper() + "\" + $principal) }
                            if ($vcfCheck.name -eq $($domain.ToUpper() + "\" + $principal)) {
                                Write-Warning -Message "Active Directory $type '$principal' already assigned the $role role in SDDC Manager"
                            }
                            else {
                                New-VCFGroup -group $principal -domain $domain -role $role | Out-Null
                                $vcfCheck = Get-VCFUser | Where-Object { $_.name -eq $($domain.ToUpper() + "\" + $principal) }
                                if ($vcfCheck.name -eq $($domain.ToUpper() + "\" + $principal)) {
                                    Write-Output "Active Directory $type '$principal' assigned the $role role in SDDC Manager Successfully"
                                }
                                else {
                                    Write-Error "Assigning Active Directory $type '$principal' the $role role in SDDC Manager Failed"
                                }
                            }
                        }
                        elseif ($type -eq "user") {
                            $vcfCheck = Get-VCFUser | Where-Object { $_.name -eq $($principal + "@" + $domain.ToUpper()) }
                            if ($vcfCheck.name -eq $($principal + "@" + $domain.ToUpper())) {
                                Write-Warning -Message "Active Directory $type '$principal' already assigned the $role role in SDDC Manager"
                            }
                            else {
                                New-VCFUser -user ($principal + "@" + $domain.ToUpper()) -role $role | Out-Null
                                $vcfCheck = Get-VCFUser | Where-Object { $_.name -eq $($principal + "@" + $domain.ToUpper()) }
                                if ($vcfCheck.name -eq $($principal + "@" + $domain.ToUpper())) {
                                    Write-Output "Active Directory $type '$principal' assigned the $role role in SDDC Manager Successfully"
                                }
                                else {
                                    Write-Error "Assigning Active Directory $type '$principal' the $role role in SDDC Manager Failed"
                                }
                            }
                        }
                    }
                    else { Write-Error "Active Directory $type '$principal' not found in the Active Directory Domain, please create and retry"
                    }
                }
                else {
                    Write-Error "Active Directory domain $domain not added as an Identity Source to vCenter Server $($ssoServer.fqdn)"
                }
            }
            else {
                Write-Error "Failed to obtain access token from SDDC Manager, check details provided"
            }
        }
        else {
            Write-Error  "Unable to authenticate to Active Directory with user '$domainBindUser' and password '$domainBindPass', verify they are correct and try again"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-SddcManagerRole

Function Set-vCenterPasswordExpiration {
    <#
		.SYNOPSIS
		Set the password expiration for the root account

    	.DESCRIPTION
    	The Set-vCenterPasswordExpiration cmdlet configures password expiration settings for the vCenter Server root
        account. The cmdlet connects to vCenter Server using the -server, -user, and -password values and then:
		- Configures the password expiration either to never expire or to expire in given number of days
		- Sets the email for warning notification to given value

    	.EXAMPLE
    	Set-vCenterPasswordExpiration -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -passwordExpires $true -email "admin@rainpole.io" -maxDaysBetweenPasswordChange 80
        This example configures the configures password expiration settings for the vCenter Server root account to expire after 80 days with email for warning set to "admin@rainpole.io"

        .EXAMPLE
		Set-vCenterPasswordExpiration -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -passwordExpires $false
        This example configures the configures password expiration settings for the vCenter Server root account to never expire
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
		[Parameter (Mandatory = $false, ParameterSetName = 'neverexpire')]
		[Parameter (Mandatory = $true, ParameterSetName = 'expire')] [ValidateNotNullOrEmpty()] [Bool]$passwordExpires,
        [Parameter (Mandatory = $true, ParameterSetName = 'expire')] [ValidateNotNullOrEmpty()] [String]$email,
        [Parameter (Mandatory = $true, ParameterSetName = 'expire')] [ValidateNotNullOrEmpty()] [String]$maxDaysBetweenPasswordChange
	)

	Try {
		$vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
		Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
		Request-vSphereApiToken -Fqdn $vcenter.fqdn -Username $vcenter.ssoadmin -Password $vcenter.ssoAdminPass -admin | Out-Null
		if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
			$pwdExpirySettings = Get-VCPasswordExpiry
			if ($passwordExpires) {
				Set-VCPasswordExpiry -passwordExpires $passwordExpires -email $email -maxDaysBetweenPasswordChange $maxDaysBetweenPasswordChange | Out-Null
			}
            else {
				Set-VCPasswordExpiry -passwordExpires $passwordExpires | Out-Null
			}
			$pwdExpirySettings = Get-VCPasswordExpiry
			if ($pwdExpirySettings.max_days_between_password_change -eq -1) {
				Write-Output "vCenter Server Appliance Password Expiration set to 'Never Expire' Successfully"
			}
            else {
				Write-Output "vCenter Server Appliance Password Expiration set to '$($pwdExpirySettings.max_days_between_password_change) days' and Email Notification set to '$($pwdExpirySettings.email)' Successfully"
			}
		}
        else {
		    Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
		}
        Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
	}
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Set-vCenterPasswordExpiration

Function Set-EsxiPasswordPolicy {
    <#
		.SYNOPSIS
    	Set ESXi password polciies

    	.DESCRIPTION
    	The Set-EsxiPasswordPolicy cmdlet configures the password and lockout policies on ESXi.
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values and then:
        - Gathers the vCenter Server details for the workload domain
        - Gathers the ESXi hosts for the cluster specificed
        - Configured all ESXi hosts in he provided cluster

    	.EXAMPLE
    	Set-EsxiPasswordPolicy -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -cluster sfo-m01-cl01 -policy "retry=5 min=disabled,disabled,disabled,disabled,15"
        This example configures all ESXi hosts within the cluster named sfo-m01-cl01 of the workload domain sfo-m01
  	#>

      Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cluster,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$policy
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            $checkCluster = Get-Cluster | Where-Object {$_.Name -eq $cluster}
            if ($checkCluster) {
                $esxiHosts = Get-Cluster $cluster | Get-VMHost
                $count = 0
                Foreach ($esxiHost in $esxiHosts) {
                    $advancedSetting = Get-VMHost | Where-Object { $_.ConnectionState -eq "Connected" } | Get-AdvancedSetting | Where-Object { $_.Name -eq "Security.PasswordQualityControl" }
                    if ($advancedSetting) {
                        Set-AdvancedSetting -AdvancedSetting $advancedSetting -Value $policy -Confirm:$false | Out-Null
                        $checkSetting = Get-VMHost | Where-Object { $_.ConnectionState -eq "Connected" } | Get-AdvancedSetting | Where-Object { $_.Name -eq "Security.PasswordQualityControl" }
                        if ($checkSetting -match $policy) {
                             Write-Output "Updated the Advanced System Setting 'Security.PasswordQualityControl' for '$esxiHost' Successfully"
                        }
                        else {
                            Write-Error "Updating the Advanced System Setting 'Security.PasswordQualityControl for '$esxiHost' Failed, please retry"
                        }
                    }
                    $count = $count + 1
                }
            }
            else {
                Write-Error "Cluster '$cluster' is not found in vCenter Server '$($vcenter.fqdn)', check the input and retry"
            }
        }
        else {
            Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
        }
        Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Set-EsxiPasswordPolicy

Function Install-WorkspaceOne {
    <#
		.SYNOPSIS
    	Deploy Workspace ONE Access Virtual Appliance

    	.DESCRIPTION
    	The Install-WorkspaceOne cmdlet deploys the Workspace ONE Access Virtual Appliance OVA.
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values to retrive the management domain
        vCenter Server details from its inventory and then:
        - Gathers vSphere configuration from vCenter Server
        - Gathers DNS and NTP configuration from SDDC Manager
        - Deploys the Workspace ONE Access Virtual Appliance

    	.EXAMPLE
    	Install-WorkspaceOne -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -wsaFqdn sfo-wsa01.sfo.rainpole.io -wsaIpAddress 192.168.31.60 -wsaGateway 192.168.31.1 -wsaSubnetMask 255.255.255.0 -wsaOvaPath F:\identity-manager.ova -wsaFolder sfo-m01-fd-wsa
        This example deploys the Workspace ONE Access Virtual Appliance named sfo-wsa01.sfo.rainpole.io into the sfo-m01-fd-wsa folder of the management domain
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaFqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaIpAddress,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaGateway,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaSubnetMask,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaFolder,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$wsaOvaPath
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("wsaOvaPath")) {
            $wsaOvaPath = Get-ExternalFileName -title "Select the Workspace ONE Access OVA file (.ova)" -fileType "ova" -location "default"
        }
        else {
            if (!(Test-Path -Path $wsaOvaPath)) {
                Write-Error  "Workspace ONE Access OVA '$wsaOvaPath' File Not Found"
                Break
            }
        }
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domainType MANAGEMENT
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
        $wsaHostname = $wsaFqdn.Split(".")[0]
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            $wsaExists = Get-VM -Name $wsaHostname -ErrorAction Ignore
            if ($wsaExists) {
                Write-Warning "A virtual machine called $wsaHostname already exists in vCenter Server $vcServer"
            }
            else {
                $dnsServer1 = (Get-VCFConfigurationDNS | Where-Object { $_.isPrimary -Match "True" }).ipAddress
                $dnsServer2 = (Get-VCFConfigurationDNS | Where-Object { $_.isPrimary -Match "False" }).ipAddress
                $cluster = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }).clusters.id) }).Name
                $datastore = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }).clusters.id) }).primaryDatastoreName
                $datacenter = (Get-Datacenter -Cluster $cluster).Name
                $avnCheck = (Get-VCFApplicationVirtualNetwork | Where-Object { $_.regionType -eq "REGION_A" }).name
                if ($avnCheck) {
                    $regionaPortgroup = (Get-VCFApplicationVirtualNetwork | Where-Object { $_.regionType -eq "REGION_A" }).name
                    $domain = (Get-VCFApplicationVirtualNetwork | Where-Object { $_.regionType -eq "REGION_A" }).domainName

                    $command = '"C:\Program Files\VMware\VMware OVF Tool\ovftool.exe" --noSSLVerify --acceptAllEulas  --allowAllExtraConfig --diskMode=thin --powerOn --name=' + $wsaHostname + ' --ipProtocol="IPv4" --ipAllocationPolicy="fixedAllocatedPolicy" --vmFolder=' + $wsaFolder + ' --net:"Network 1"=' + $regionaPortgroup + '  --datastore=' + $datastore + ' --X:injectOvfEnv --prop:vamitimezone=' + $timezone + '  --prop:vami.ip0.IdentityManager=' + $wsaIpAddress + ' --prop:vami.netmask0.IdentityManager=' + $wsaSubnetMask + ' --prop:vami.hostname=' + $wsaFqdn + ' --prop:vami.gateway.IdentityManager=' + $wsaGateway + ' --prop:vami.domain.IdentityManager=' + $domain + ' --prop:vami.searchpath.IdentityManager=' + $domain + ' --prop:vami.DNS.IdentityManager=' + $dnsServer1 + ',' + $dnsServer2 + ' "' + $wsaOvaPath + '"  "vi://' + $vcenter.ssoAdmin + ':' + $vcenter.ssoAdminPass + '@' + $vcenter.fqdn + '/' + $datacenter + '/host/' + $cluster + '/"'
                    Invoke-Expression "& $command" -ErrorAction Ignore
                    $wsaExists = Get-VM -Name $wsaHostname -ErrorAction Ignore
                    if ($wsaExists) {
                        $Timeout = 900  ## seconds
                        $CheckEvery = 15  ## seconds
                        Try {
                            $timer = [Diagnostics.Stopwatch]::StartNew()  ## Start the timer
                            Write-Output "Waiting for $wsaIpAddress to become pingable."
                            While (-not (Test-Connection -ComputerName $wsaIpAddress -Quiet -Count 1)) {
                                ## If the timer has waited greater than or equal to the timeout, throw an exception exiting the loop
                                if ($timer.Elapsed.TotalSeconds -ge $Timeout) {
                                    Throw "Timeout Exceeded. Giving up on ping availability to $wsaIpAddress"
                                }
                                Start-Sleep -Seconds $CheckEvery  ## Stop the loop every $CheckEvery seconds
                            }
                        }
                        Catch {
                            Write-Error "Failed to get a Response from $wsaFqdn"
                        }
                        Finally {
                            $timer.Stop()  ## Stop the timer
                        }
						$Timeout = 900  ## seconds
                        $CheckEvery = 5  ## seconds
						Try {
                            $timer = [Diagnostics.Stopwatch]::StartNew()  ## Start the timer
							$uri = "https://" + $wsaFqdn + "/SAAS/jersey/manager/api/system/health"
							Write-Output "Initial connection made, waiting for $wsaFqdn to fully boot and services to start. Be warned, this takes a long time."
                            While ($timer.Elapsed.TotalSeconds -lt $Timeout) {
                                ## If the timer has waited greater than or equal to the timeout, throw an exception exiting the loop
								Try {
									$response = Invoke-RestMethod $uri -Method 'GET' -SessionVariable webSession -ErrorAction Ignore
									if ($response.AllOk -eq "true") {
										Write-Output "Deployment of $wsaFqdn using $wsaOvaPath completed Successfully"
										break
									}
								}
                                Catch {
									Write-Output "Waiting for $wsaFqdn to fully boot up. Checking every $CheckEvery seconds"
								}
                                Start-Sleep -Seconds $CheckEvery  ## Stop the loop every $CheckEvery seconds
                            }
							if ($timer.Elapsed.TotalSeconds -ge $Timeout) {
                                    Write-Error "$wsaFqdn failed to initialize properly. Please delete the VM from $($vcenter.fqdn) and retry"
                            }
                        }
                        Catch {
							Debug-ExceptionWriter -object $_
                        }
                        Finally {
                            $timer.Stop()  ## Stop the timer
                        }
                    }
                    else {
                        Write-Error "Workspace ONE Access Failed to deploy"
                    }
                }
                else {
                    Write-Error  "Application Virtual Networks have not been configured on $server, unable to find REGION_A details. Configure them and try again"
                }
            }
            Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
        }
        else {
            Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Install-WorkspaceOne

Function Initialize-WorkspaceOne {
    <#
		.SYNOPSIS
    	Initalize Workspace ONE Access Virtual Appliance

    	.DESCRIPTION
    	The Initialize-WorkspaceOne cmdlet performs the initial configuration of Workspace ONE Access Virtual Appliance.
        - Sets the default password for the admin, root and SSH Users
        - Initializes the internal PostgrsSQL database
        - Activates the default connector

    	.EXAMPLE
    	Initialize-WorkspaceOne -wsaFqdn sfo-wsa01.sfo.rainpole.io -adminPass VMw@re1! -rootPass VMw@re1! -sshUserPass VMw@re1!
        This example initialzes the Workspace ONE Access Virtual Appliance sfo-wsa01.sfo.rainpole.io and sets the default passwords for admin, root and SSH User
  	#>

      Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaFqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$adminPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$rootPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sshUserPass
    )

    Try {
        $baseUri = "https://" + $wsaFqdn + ":8443"
        $uri = $baseUri + "/login"
        $response = Invoke-RestMethod $uri -Method 'GET' -SessionVariable webSession
        $response | Out-File wsaResponse.txt
        $tokenSource = (Select-String -Path wsaResponse.txt -Pattern 'window.ec_wiz.vk =')
        $token = ($tokenSource -Split ("'"))[1]
        Remove-Item wsaResponse.txt
        if ($token) {
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
            $headers.Add("X-Vk", "$token")
            $headers.Add("Accept", "application/json")
            # Set the Admin Password
            $body = "password=" + $adminPass + "&confpassword=" + $adminPass
            $uri = $baseUri + "/cfg/changePassword"
            Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body -WebSession $webSession | Out-Null
            # Set the Root & SSHUser Passwords
            $body = "rootPassword=" + $rootPass + "&sshuserPassword=" + $sshUserPass
            $uri = $baseUri + "/cfg/system"
            Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body -WebSession $webSession  | Out-Null
            # Initalize the Internal Database
            $uri = $baseUri + "/cfg/setup/initialize"
            Invoke-RestMethod $uri -Method 'POST' -Headers $headers -WebSession $webSession  | Out-Null
            # Activate the default connector
            $uri = $baseUri + "/cfg/setup/activateConnector"
            Invoke-RestMethod $uri -Method 'POST' -Headers $headers -WebSession $webSession  | Out-Null
            Write-Output "Initial configuration of Workspace ONE Access Virtual Appliance $wsaFqdn completed Succesfully"
        }
        else {
            Write-Warning "Initial configuration of Workspace ONE Access Virtual Appliance $wsaFqdn has already been performed"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Initialize-WorkspaceOne

Function Set-WorkspaceOneNtpConfig {
    <#
		.SYNOPSIS
    	Configure NTP Server on Workspace ONE Access Appliance

    	.DESCRIPTION
    	The Set-WorkspaceOneNtpConfig cmdlet configures the NTP Server details of the Workspace ONE Access Appliance
        using the same NTP Server configuration as SDDC Manager

    	.EXAMPLE
    	Set-WorkspaceOneNtpConfig -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -wsaFqdn sfo-wsa01.sfo.rainpole.io -rootPass VMw@re1!
        This example configures the Workspace ONE Access Virtual Appliance sfo-wsa01.sfo.rainpole.io with the same NTP Servers defined in SDDC Manager
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaFqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$rootPass
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domainType MANAGEMENT
        if (Test-Connection -ComputerName ($wsaFqdn) -Quiet -Count 1) {
            Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
            if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
                $ntpServer = (Get-VCFConfigurationNTP).ipAddress
                $vmName = $wsaFqdn.Split(".")[0]
                if ($checkVm = (Get-VM -Name $vmName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue )) {
                    $scriptCommand = '/usr/local/horizon/scripts/ntpServer.hzn --get'
                    $output = Invoke-VMScript -VM $vmName -ScriptText $scriptCommand -GuestUser root -GuestPassword $rootPass -Server $vcenter.fqdn
                    if (($output.ScriptOutput).Contains($ntpServer)) {
                        Write-Warning -Message "NTP Server '$ntpServer' already configured on Workspace One Access Virtual Appliance $vmName"
                    }
                    else {
                        $scriptCommand = '/usr/local/horizon/scripts/ntpServer.hzn --set ' + $ntpServer
                        $output = Invoke-VMScript -VM $vmName -ScriptText $scriptCommand -GuestUser root -GuestPassword $rootPass -Server $vcenter.fqdn
                        $scriptCommand = '/usr/local/horizon/scripts/ntpServer.hzn --get'
                        $output = Invoke-VMScript -VM $vmName -ScriptText $scriptCommand -GuestUser root -GuestPassword $rootPass -Server $vcenter.fqdn
                        if (($output.ScriptOutput).Contains($ntpServer)) {
                            Write-Output "Configured NTP Server '$ntpServer' on Workspace One Access Virtual Appliance $vmName Successfully"
                        }
                        else {
                            Write-Error "Configuring NTP Server '$ntpServer' on Workspace One Access Virtual Appliance $vmName Failed"
                        }
                    }
                }
                else {
                    Write-Error  "A virtual machine with name $vmName not found in vCenter Server $($vcenter.fqdn)"
                }
                Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
            }
            else {
                Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error "Workspace ONE Access Appliance $wsaFqdn is not contactable"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Set-WorkspaceOneNtpConfig

Function Install-WorkspaceOneCertificate {
    <#
		.SYNOPSIS
    	Install a Signed Certificate on Workspace ONE Access Appliance

    	.DESCRIPTION
    	The Install-WorkspaceOneCertificate cmdlet replaces the certificate on the Workspace ONE Access

    	.EXAMPLE
    	Install-WorkspaceOneCertificate -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -wsaFqdn sfo-wsa01.sfo.rainpole.io -rootPass VMw@re1! -sshUserPass VMw@re1!
        This example install the Workspace ONE Access Virtual Appliance sfo-wsa01.sfo.rainpole.io with a the signed certificate provided
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaFqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$rootPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sshUserPass,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$rootCa,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$wsaCertKey,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$wsaCert
    )

    Try {

        if (!$PsBoundParameters.ContainsKey("rootCa")) {
            $rootCa = Get-ExternalFileName -title "Select the Root CA Certificate File (.cer)" -fileType "cer" -location "default"
        }
        elseif ($PsBoundParameters.ContainsKey("rootCa")) {
            if (!(Test-Path -Path $rootCa)) {
                Write-Error  "Certificate (.cer) for Root Certificate Authority '$rootCa' File Not Found"
                Break
            }
        }

        if (!$PsBoundParameters.ContainsKey("wsaCertKey")) {
            $wsaCertKey = Get-ExternalFileName -title "Select the Workspace ONE Access Certificate Key (.key)" -fileType "key" -locaion "default"
        }
        elseif ($PsBoundParameters.ContainsKey("wsaCertKey")) {
            if (!(Test-Path -Path $wsaCertKey)) {
                Write-Error  "Certificate Key (.key) for Workspace ONE Access '$wsaCertKey' File Not Found"
                Break
            }
        }

        if (!$PsBoundParameters.ContainsKey("wsaCert")) {
            $wsaCert = Get-ExternalFileName -title "Select the Workspace ONE Access Certificate File (.cer)" -fileType "cer" -location "default"
        }
        elseif ($PsBoundParameters.ContainsKey("wsaCert")) {
            if (!(Test-Path -Path $wsaCert)) {
                Write-Error  "Certificate (.cer) for Workspace ONE Access '$wsaCert' File Not Found"
                Break
            }
        }

        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domainType MANAGEMENT
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            $vmName = $wsaFqdn.Split(".")[0]
            Get-Item $rootCa | Copy-VMGuestFile -Destination '/tmp' -VM $vmName -LocalToGuest -GuestUser root -GuestPassword $rootPass -Force
            Get-Item $wsaCertKey | Copy-VMGuestFile -Destination '/tmp' -VM $vmName -LocalToGuest -GuestUser root -GuestPassword $rootPass -Force
            Get-Item $wsaCert | Copy-VMGuestFile -Destination '/tmp' -VM $vmName -LocalToGuest -GuestUser root -GuestPassword $rootPass -Force

            $scriptCommand = 'echo "yes" | /usr/local/horizon/scripts/installExternalCertificate.hzn --ca /tmp/' + (Split-Path -Leaf $rootCa) + ' --cert /tmp/' + (Split-Path -Leaf $wsaCert) + ' --key /tmp/' + (Split-Path -Leaf $wsaCertKey)
            $output = Invoke-VMScript -VM $vmName -ScriptText $scriptCommand -GuestUser root -GuestPassword $rootPass -Server $vcenter.fqdn
            Write-Output "Installed Signed Certifcate $wsaCert on Workspace One Access Virtual Appliance $wsaFqdn Successfully"
            Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
        }
        else {
            Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Install-WorkspaceOneCertificate

Function Set-WorkspaceOneSmtpConfig {
    <#
		.SYNOPSIS
    	Configure SMTP Server on Workspace ONE Access Appliance

    	.DESCRIPTION
    	The Set-WorkspaceOneSmtpConfig cmdlet configures the SMTP Server details of the Workspace ONE Access Appliance

    	.EXAMPLE
    	Set-WorkspaceOneSmtpConfig -server sfo-wsa01.sfo.rainpole.io -user admin -pass VMw@re1! -smtpFqdn smtp.sfo.rainpole.io -smtpPort 25 -smtpEmail sfo-wsa@rainpole.io
        This example configures the Workspace ONE Access Virtual Appliance sfo-wsa01.sfo.rainpole.io with the SMTP Server details
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$smtpFqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$smtpPort,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$smtpEmail,
        [Parameter (Mandatory = $false)] [String]$smtpEmailPassword
    )

    Try {
        Request-WSAToken -fqdn $server -user $user -pass $pass | Out-Null
        if ($sessionToken) {
            if (-not $PsBoundParameters.ContainsKey("smtpEmailPassword")) {
                Set-WSASmtpConfiguration -fqdn $smtpFqdn -port $smtpPort -user $smtpEmail | Out-Null
            }
            if ($PsBoundParameters.ContainsKey("smtpEmailPassword")) {
                Set-WSASmtpConfiguration -fqdn $smtpFqdn -port $smtpPort -user $smtpEmail -pass $smtpEmailPassword | Out-Null
            }
            Write-Output "Completed SMTP configuration for Workspace ONE Access '$server' Successfully"
        }
        else {
            Write-Error  "Failed to obtain access token from Workspace One Access appliance '$server', check details provided"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Set-WorkspaceOneSmtpConfig

Function Add-WorkspaceOneDirectory {
    <#
		.SYNOPSIS
    	Configure Active Directory LDAP Directory in Workspace ONE Access Appliance

    	.DESCRIPTION
    	The Add-WorkspaceOneDirectory cmdlet configures Active Directory LDAP Directory in Workspace ONE Access Appliance

    	.EXAMPLE
    	Add-WorkspaceOneDirectory -server sfo-wsa01.sfo.rainpole.io -user admin -pass VMw@re1! -domain sfo.rainpole.io -baseDn "OU=VVD,DC=sfo,DC=rainpole,DC=io" -bindUserDn "CN=svc-wsa-ad,OU=VVD,DC=sfo,DC=rainpole,DC=io" -bindUserPass VMw@re1! -adGroups "gg-nsx-enterprise-admins","gg-nsx-network-admins","gg-nsx-auditors","gg-wsa-admins","gg-wsa-directory-admins","gg-wsa-read-only" -protocol "ldaps" -certificate "F:\platformtools-l1-dev\certificates\Root64.pem"
        This example configures the domain sfo.rainpole.io as a directory source in Workspace ONE Access Virtual Appliance and syncronises the groups provided
  	#>

      Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$baseDnUser,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$baseDnGroup,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$bindUserDn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$bindUserPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Array]$adGroups,
        [Parameter (Mandatory = $true)] [ValidateSet("ldap", "ldaps")] [String]$protocol,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$certificate
    )

    if (!$PsBoundParameters.ContainsKey("certificate") -and ($protocol -eq "ldaps")) {
        $certificate = Get-ExternalFileName -title "Select the Root CA Certificate File (.pem)" -fileType "pem" -location "default"
    }
    elseif ($protocol -eq "ldaps") {
        if (!(Test-Path -Path $certificate)) {
            Write-Error  "Certificate (cer) for Root Certificate Authority '$certificate' File Not Found"
            Break
        }
    }

    Try {
        Request-WSAToken -fqdn $server -user $user -pass $pass | Out-Null
        if ($sessionToken) {
            $checkAdAuthentication = Test-ADAuthentication -user ($bindUserDn.Split(",")[0]).Split("=")[1] -pass $bindUserPass -server $domain -domain $domain
            if ($checkAdAuthentication -contains "2") {
                $checkDirectoryExist = Get-WSADirectory | Where-Object { ($_.name -eq $domain) }
                if (!$checkDirectoryExist) {
                    if ($protocol -eq "ldaps") {
                        $directory = Add-WSALdapDirectory -domainName $domain -baseDn $baseDnUser -bindDn $bindUserDn -certificate $certificate
                    }
                    else{
                        $directory = Add-WSALdapDirectory -domainName $domain -baseDn $baseDnUser -bindDn $bindUserDn
                    }
                    $connector = Get-WSAConnector
                    Set-WSABindPassword -directoryId $directory.directoryConfigId -connectorId $connector.instanceId -pass $bindUserPass | Out-Null
                    $adUserJson = '{ "identityUserInfo": { "' + $bindUserDn + '": { "selected": true }, "' + $baseDnUser + '": { "selected": true }}}'
                    $mappedGroupObject = @()
                    foreach ($group in $adGroups) {
                        $adGroupDetails = Get-ADPrincipalGuid -domain $domain -user ($bindUserDn.Split(',')[0]).Split('=')[1] -pass $bindUserPass -principal $group
                        if ($adGroupDetails) {
                            $groupsObject = @()
                            $groupsObject += [pscustomobject]@{
                                'horizonName' = $adGroupDetails.Name
                                'dn'          = $adGroupDetails.DistinguishedName
                                'objectGuid'  = $adGroupDetails.ObjectGuid
                                'groupBaseDN' = $baseDnGroup
                                'source'      = "DIRECTORY"
                            }
                            $mappedGroupObject += [pscustomobject]@{
                                'mappedGroup' = ($groupsObject | Select-Object -Skip 0)
                                'selected'    = $true
                            }
                        }
                        else {
                            Write-Error "Group $group is not available in Active Directory Domain"
                        }
                    }
                    $mappedGroupObjectData = @()
                    $mappedGroupObjectData += [pscustomobject]@{
                        'mappedGroupData' = $mappedGroupObject
                        'selected'        = $false
                    }
                    $identityGroupObject = @()
                    $identityGroupObject += [pscustomobject]@{
                        $baseDnGroup = ($mappedGroupObjectData | Select-Object -Skip 0)
                    }
                    $adGroupObject = @()
                    $adGroupObject += [pscustomobject]@{
                        'identityGroupInfo'         = ($identityGroupObject | Select-Object -Skip 0)
                        'excludeNestedGroupMembers' = $false
                    }
                    $adGroupJson = $adGroupObject | ConvertTo-Json -Depth 10

                    #$adUserJson
                    #$adGroupJson
                    Set-WSADirectoryUser -directoryId $directory.directoryConfigId -json $adUserJson | Out-Null
                    Set-WSADirectoryGroup -directoryId $directory.directoryConfigId -json $adGroupJson | Out-Null
                    Set-WSASyncSetting -directoryId $directory.directoryConfigId | Out-Null
                    Start-WSADirectorySync -directoryId $directory.directoryConfigId | Out-Null
                    Write-Output "Active Directory LDAP Directory created in Workspace One Access Successfully"
                }
                else {
                    Write-Warning  "LDAP Directory for $domain already exists, skipping the creation"
                }
            }
            else {
                Write-Error "Domain User $domainJoinUser Authentication Failed"
            }
        }
        else {
            Write-Error  "Failed to obtain access token from Workspace One Access appliance '$server', check details provided"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-WorkspaceOneDirectory

Function Set-WorkspaceOneNsxtIntegration {
    <#
		.SYNOPSIS
    	Integrate NSX Manager with Workspace ONE Access

    	.DESCRIPTION
    	The Set-WorkspaceOneNsxtIntegration cmdlet configures integration between NSX Manager and Workspace ONE Access. The cmdlet connects
        to SDDC Manager using the -server, -user, and -password values to retrive the NSX Manager details from its inventory and then:
        - Creates a service client within Workspace ONE Access
        - Enables the integration between NSX Manager and Workspace ONE Access

    	.EXAMPLE
    	Set-WorkspaceOneNsxtIntegration -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -wsaFqdn sfo-wsa01.sfo.rainpole.io -wsaUser admin -wsaPass VMw@re1!
        This example integrates the management domain NSX Manager instance with Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaFqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaUser,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaPass
    )

    Try {
        $nsxtManagerDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain
        Request-NsxToken -fqdn $nsxtManagerDetails.fqdn -username $nsxtManagerDetails.adminUser -password $nsxtManagerDetails.AdminPass | Out-Null
        if ($accessToken) {
            $clientId = $nsxtManagerDetails.fqdn.Split(".")[0] + "-oauth"
            $command = 'openssl s_client -connect ' + $wsaFqdn + ':443 2>&1 | openssl x509 -sha256 -fingerprint -noout'
            $wsaThumbprint = (Invoke-Expression "& $command").Split("=")[1]
            if (!$wsaThumbprint) {
                Write-Error "Obtain SSL thumbprint for Workspace ONE Access Appliance '$wsaFqdn' failed, check details and try again"
                Break
            }
            Request-WSAToken -fqdn $wsaFqdn -user $wsaUser -pass $wsaPass | Out-Null
            if ($sessionToken) {
                $sharedSecret = (Get-WSAOAuthToken).message
                $clientExists = Get-WSAClient | Where-Object { $_.clientId -eq $clientId }
                if (!$clientExists) {
                    Add-WSAClient -clientId $clientId -sharedSecret $sharedSecret | Out-Null
                    $clientExists = Get-WSAClient | Where-Object { $_.clientId -eq $clientId }
                    if ($clientExists) {
                        Write-Output "Created Service client '$clientId' in Workspace ONE Access Successfully"
                    }
                    else {
                        Write-Error "Creation of Service client '$clientId' in Workspace ONE Access Failed, check inputs and try again"
                        Break
                    }
                }
                else {
                    Write-Warning "Service client '$clientId' in Workspace ONE Access already exists, skipping the creation"
                }
                $vidmExists = Get-NsxtVidm
                if ($vidmExists) {
                    $clientIdSecret = (Get-WSAClient -clientId $clientId).secret
                    Set-NsxtVidm -wsaHostname $wsaFqdn -thumbprint $wsaThumbprint -clientId $clientId -sharedSecret $clientIdSecret -nsxHostname $nsxtManagerDetails.fqdn | Out-Null
                    Write-Output "Updated integration between NSX-T Manager '$($nsxtManagerDetails.fqdn) and Workspace ONE Acccess '$wsaFqdn' Successfully"
                }
                else {
                    Set-NsxtVidm -wsaHostname $wsaFqdn -thumbprint $wsaThumbprint -clientId $clientId -sharedSecret $sharedSecret -nsxHostname $nsxtManagerDetails.fqdn | Out-Null
                    Write-Output "Created integration between NSX-T Manager '$($nsxtManagerDetails.fqdn) and Workspace ONE Acccess '$wsaFqdn' Successfully"
                }
            }
            else {
                Write-Error  "Failed to obtain access token from Workspace ONE Access appliance '$wsaFqdn', check details provided"
            }
        }
        else {
            Write-Error "Failed to obtain access token from NSX-T Data Center '$($nsxtManagerDetails.fqdn)', check details provided"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Set-WorkspaceOneNsxtIntegration

Function Add-NsxtVidmGroupRole {
    <#
		.SYNOPSIS
    	Configure Role-Based Access Control for NSX Manager

    	.DESCRIPTION
    	The Add-NsxtVidmGroupRole cmdlet configures role assignments in NSX Manager. The cmdlet connects to SDDC
        Manager using the -server, -user, and -password values to retrive the NSX Manager details from its inventory and then:
        - Assigns Active Directory groups to NSX Manager roles

    	.EXAMPLE
    	Add-NsxtVidmGroupRole -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -group "gg-nsx-enterprise-admins@sfo.rainpole.io" -role enterprise_admin
        This example assigns the gg-nsx-enterprise-admins@sfo.rainpole.io group with the enterprise_admin role in NSX Manager
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$group,
        [Parameter (Mandatory = $true)] [ValidateSet("lb_admin", "security_engineer", "vpn_admin", "network_op", "netx_partner_admin", "gi_partner_admin", "security_op", "network_engineer", "lb_auditor", "auditor", "enterprise_admin")] [string]$role
    )

    Try {
        $nsxtManagerDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain
        Request-NsxToken -fqdn $nsxtManagerDetails.fqdn -username $nsxtManagerDetails.adminUser -password $nsxtManagerDetails.AdminPass | Out-Null
        if ($accessToken) {
            $groupExists = Get-NsxtUser | Where-Object { $_.name -eq $group }
            if (!$groupExists) {
                Set-NsxtRole -principal $group -type remote_group -role $role -identitySource VIDM | Out-Null
                $groupExists = Get-NsxtUser | Where-Object { $_.name -eq $group }
                if ($groupExists) {
                    Write-Output "Assigned group '$group' the role' $role' in NSX-T Data Center for Workload Domain '$domain' Successfully"
                }
                else {
                    Write-Error "Failed to assign group '$group' the role '$role' in NSX-T Data Center for Workload Domain '$domain', check details and retry"
                }
            }
            else {
                Write-Warning "Group '$group' has already been assigned the role in NSX-T Data Center for Workload Domain '$domain', skipping the creation"
            }
        }
        else {
            Write-Error "Failed to obtain access token from NSX-T Data Center '$($nsxtManagerDetails.fqdn)', check details provided"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-NsxtVidmGroupRole

Function Add-WorkspaceOneRole {
    <#
        .SYNOPSIS
        Assign Active Directory Groups to Roles in the Workspace ONE Access

        .DESCRIPTION
        The Add-WorkspaceOneRole cmdlet assigns roles to Active Directory groups provided to manage administrative
        access to the Workspace ONE Access instance.

        .EXAMPLE
        Add-WorkspaceOneRole -server sfo-wsa01.sfo.rainpole.io -user admin -pass VMw@re1! -group "gg-wsa-admins" -role "Super Admin"
        This example adds the group gg-wsa-admins the Super Admin role
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$group,
        [Parameter (Mandatory = $true)] [ValidateSet("Super Admin", "Directory Admin", "ReadOnly Admin")] [String]$role
    )

    Try {
        Request-WSAToken -fqdn $server -user $user -pass $pass | Out-Null
        if ($sessionToken) {
            $roleId = Get-WSARoleId -role $role
            if (!$roleId) {
                Write-Error "Unable to find role id $roleId for role $role in Workspace ONE Access instance $server)"
            }
            else {
                $groupDetails = Get-WSAActiveDirectoryGroupDetail -group $group
                $groupId = $groupDetails.Resources.id
                if (!$groupId) {
                    Write-Error "Unable to find the group $group in Workspace ONE Access instance $server"
                }
                else {
                    $associations = Get-WSARoleAssociation -roleId $roleId
                    $assign = $true
                    if ($associations.groups) {
                        if ($associations.groups -contains $groupId) {
                            Write-Warning "Already assigned group $group to role $role in Workspace ONE Access instance $server"
                            $assign = $false
                        }
                    }

                    if ($assign) {
						if ($role -ne "ReadOnly Admin") {
							Write-Output "Update the Administrator Role Member with $group group"
							$administratorRole = Get-WsaRole | Where-Object { $_.displayName -eq "Administrator" }
							$adminId =  $administratorRole.id
							Set-WSARoleMember -groupId $groupId -id $adminId
						}
                        $response = Add-WSARoleAssociation -roleId $roleId -groupId $groupId
                        if ($response.operations.code -eq "200") {
                            Write-Output "Assigned group $group to the role $role in Workspace ONE Access instance $server Successfully"
                        }
                        elseif ($response.operations.code -eq "409") {
                            Write-Warning "$($response.operations.reason)"
                        }
                        else {
                            Write-Error "$($response.operations.reason)"
                        }
                    }
                }
            }
        }
        else {
            Write-Error  "Failed to obtain access token from Workspace One Access appliance '$server', check details provided"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-WorkspaceOneRole

Function Get-NsxtManagerAuthenticationPolicy {
    <#
		.SYNOPSIS
    	Retrieve the current Authentication Policy from NSX Manager Nodes

    	.DESCRIPTION
    	The Get-NsxtManagerAuthenticationPolicy cmdlet retrieves the current Authentication policy from each NSX
        manager nodes for a workload domain. The cmdlet connects to SDDC Manager using the -server, -user, and
        -password values to retrive the NSX-T Data Center details from its inventory and then:
        - Output the following Authentication policy on each NSX manager node.
			a) api_failed_auth_lockout_period (in sec)
			b) api_failed_auth_reset_period (in sec)
			c) api_max_auth_failures (in attempt)
			d) cli_failed_auth_lockout_period (in sec)
			e) cli_max_auth_failures (in attempt)
			f) minimum_password_length (in characters)

    	.EXAMPLE
    	Get-NsxtManagerAuthenticationPolicy -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01
        This example retrieves the current Authentication policy from NSX manager nodes in sfo-m01 workload domain
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain
    )

    Try {
        $nsxtManagerDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain -listNodes

		foreach ($nsxtManagerNode in $nsxtManagerDetails.nodes) {
			Request-NsxToken -fqdn $nsxtManagerNode.fqdn -username $nsxtManagerDetails.adminUser -password $nsxtManagerDetails.AdminPass | Out-Null
			if ($accessToken) {
				$response = Get-NsxtManagerAuthPolicy -nsxtManagerNode $nsxtManagerNode.fqdn
				Write-Output "Showing $($nsxtManagerNode.fqdn), results: $response"
			}
			else {
				Write-Error "Failed to obtain access token from NSX-T Data Center '$($nsxtManagerDetails.fqdn)', check details provided"
			}
		}
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Get-NsxtManagerAuthenticationPolicy

Function Set-NsxtManagerAuthenticationPolicy {
    <#
		.SYNOPSIS
    	Configure Authentication Password Policy NSX Manager Nodes

    	.DESCRIPTION
    	The Set-NsxtManagerAuthenticationPolicy cmdlet configures Authentication policy within NSX manager nodes within
        a workload domain. The cmdlet connects to SDDC Manager using the -server, -user, and -password values to
        retrive the NSX-T Data Center details from its inventory and then:
        - Configure the following Authentication password policy on each NSX manager.
			a) api_failed_auth_lockout_period (in sec)
			b) api_failed_auth_reset_period (in sec)
			c) api_max_auth_failures (in attempt)
			d) cli_failed_auth_lockout_period (in sec)
			e) cli_max_auth_failures (in attempt)
			f) minimum_password_length (in characters)

    	.EXAMPLE
    	Set-NsxtManagerAuthenticationPolicy -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -apiLockoutPeriod 900 -apiResetPeriod 120 -apiMaxAttempt 5 -cliLockoutPeriod 900 -cliMaxAttempt 5 -minPasswdLength 15
        This example configures the Authentication password policy in NSX manager nodes in sfo-m01 workload domain
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$apiLockoutPeriod,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$apiResetPeriod,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$apiMaxAttempt,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$cliLockoutPeriod,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$cliMaxAttempt,
        [Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$minPasswdLength,
        [Parameter (Mandatory = $false)] [ValidateSet("true","false")] [String]$detail="true"
    )

    Try {
        $nsxtManagerDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain -listNodes
		foreach ($nsxtManagerNode in $nsxtManagerDetails.nodes) {
			Request-NsxToken -fqdn $nsxtManagerNode.fqdn -username $nsxtManagerDetails.adminUser -password $nsxtManagerDetails.AdminPass | Out-Null
			if ($accessToken) {
				$response = Get-NsxtManagerAuthPolicy -nsxtManagerNode $nsxtManagerNode.fqdn
				if (!$PsBoundParameters.ContainsKey("apiLockoutPeriod")){
					$apiLockoutPeriod = [int]$response.api_failed_auth_lockout_period
				}
				if (!$PsBoundParameters.ContainsKey("apiResetPeriod")){
					$apiResetPeriod = [int]$response.api_failed_auth_reset_period
				}
				if (!$PsBoundParameters.ContainsKey("apiMaxAttempt")){
					$apiMaxAttempt = [int]$response.api_max_auth_failures
				}
				if (!$PsBoundParameters.ContainsKey("cliLockoutPeriod")){
					$cliLockoutPeriod = [int]$response.cli_failed_auth_lockout_period
				}
				if (!$PsBoundParameters.ContainsKey("cliMaxAttempt")){
					$cliMaxAttempt = [int]$response.cli_max_auth_failures
				}
				if (!$PsBoundParameters.ContainsKey("minPasswdLength")){
					$minPasswdLength = [int]$response.minimum_password_length
				}
				$response = Set-NsxtManagerAuthPolicy -nsxtManagerNode $nsxtManagerNode.fqdn -api_lockout_period $apiLockoutPeriod -api_reset_period $apiResetPeriod -api_max_attempt $apiMaxAttempt -cli_lockout_period $cliLockoutPeriod -cli_max_attempt $cliMaxAttempt -min_passwd_length $minPasswdLength
				if ($detail -eq "true") {
                    Write-Output "Configured the Authentication Policy on NSX Manager '$($nsxtManagerNode.fqdn)' for Workload Domain '$domain' Successfully"
                }
			}
			else {
				Write-Error "Failed to obtain access token from NSX Data Center '$($nsxtManagerDetails.fqdn)', check details provided"
			}
		}
        if ($detail -eq "false") {
            Write-OutPut "Configured Authentication Password Policy on all NSX Manager Nodes Successfully"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Set-NsxtManagerAuthenticationPolicy

Function Get-NsxtEdgeNodeAuthenticationPolicy {
    <#
		.SYNOPSIS
    	Retrieve Authentication Policy from NSX Edge Nodes

    	.DESCRIPTION
    	The Get-NsxtEdgeNodeAuthenticationPolicy cmdlet retrieves the current Authentication policy from NSX Edge
        nodes within a workload domain. The cmdlet connects to SDDC Manager using the -server, -user, and -password
        values to retrive the NSX-T Data Center details from its inventory and then:
        -Output the following Authentication policy on each NSX Edge Nodes.
			a) cli_failed_auth_lockout_period (in sec)
			b) cli_max_auth_failures (in attempt)
			c) minimum_password_length (in characters)

    	.EXAMPLE
    	Get-NsxtEdgeNodeAuthenticationPolicy -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01
        This example retrieving the Authentication policy for NSX Edge nodes in sfo-m01 workload domain
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain
    )

    Try {
        $nsxtManagerDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain -listNodes
		Request-NsxToken -fqdn $nsxtManagerDetails.fqdn -username $nsxtManagerDetails.adminUser -password $nsxtManagerDetails.AdminPass | Out-Null
		$nsxtEdgeNodes = (Get-NsxtEdgeCluster | Where-Object {$_.member_node_type -eq "EDGE_NODE"})
		if ($accessToken) {
			foreach ($nsxtEdgeNode in $nsxtEdgeNodes.members) {
				$response = Get-NsxtEdgeNodeAuthPolicy -nsxtManager $nsxtManagerDetails.fqdn -nsxtEdgeNodeID $nsxtEdgeNode.transport_node_id
				Write-Output "Retrieving $($nsxtEdgeNode.transport_node_id), results: $response"
			}
		}
		else {
				Write-Error "Failed to obtain access token from NSX-T Data Center '$($nsxtManagerDetails.fqdn)', check details provided"
		}
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Get-NsxtEdgeNodeAuthenticationPolicy

Function Set-NsxtEdgeNodeAuthenticationPolicy {
    <#
		.SYNOPSIS
    	Configure Authentication Policy NSX Edge Nodes

    	.DESCRIPTION
    	The Set-NsxtEdgeNodeAuthenticationPolicy cmdlet configures the Authentication policy within NSX Edge nodes.
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values to retrive the NSX-T
        Data Center details from its inventory and then:
        - Configure the following Authentication policy on each NSX Edge Node.
			a) cli_failed_auth_lockout_period (in sec)
			b) cli_max_auth_failures (in attempt)
			c) minimum_password_length (in characters)

    	.EXAMPLE
    	Set-NsxtEdgeNodeAuthenticationPolicy -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -cliLockoutPeriod 900 -cliMaxAttempt 5 -minPasswdLength 15
        This example configures the Authentication policy of the NSX Edges nodes in sfo-m01 workload domain
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$cliLockoutPeriod,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$cliMaxAttempt,
        [Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$minPasswdLength,
        [Parameter (Mandatory = $false)] [ValidateSet("true","false")] [String]$detail="true"
    )

	Try {
        $nsxtManagerDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain -listNodes
		Request-NsxToken -fqdn $nsxtManagerDetails.fqdn -username $nsxtManagerDetails.adminUser -password $nsxtManagerDetails.AdminPass | Out-Null
		$nsxtEdgeNodes = (Get-NsxtEdgeCluster | Where-Object {$_.member_node_type -eq "EDGE_NODE"})
		if ($accessToken) {
			foreach ($nsxtEdgeNode in $nsxtEdgeNodes.members) {
				$response = Get-NsxtEdgeNodeAuthPolicy -nsxtManager $nsxtManagerDetails.fqdn -nsxtEdgeNodeID $nsxtEdgeNode.transport_node_id
				if (!$PsBoundParameters.ContainsKey("cliLockoutPeriod")){
					$cliLockoutPeriod = [int]$response.cli_failed_auth_lockout_period
				}
				if (!$PsBoundParameters.ContainsKey("cliMaxAttempt")){
					$cliMaxAttempt = [int]$response.cli_max_auth_failures
				}
				if (!$PsBoundParameters.ContainsKey("minPasswdLength")){
					$minPasswdLength = [int]$response.minimum_password_length
				}
				$response = Set-NsxtEdgeNodeAuthPolicy -nsxtManager $nsxtManagerDetails.fqdn -nsxtEdgeNodeID $nsxtEdgeNode.transport_node_id -cli_lockout_period $cliLockoutPeriod -cli_max_attempt $cliMaxAttempt -min_passwd_length $minPasswdLength
				if ($detail -eq "true") {
                    Write-Output "Configured the Authentication Policy on NSX Edge nodes for Workload Domain '$domain' Successfully"
                }
			}
		}
		else {
				Write-Error "Failed to obtain access token from NSX-T Data Center '$($nsxtManagerDetails.fqdn)', check details provided"
		}
        if ($detail -eq "false") {
            Write-OutPut "Configured Authentication Password Policy on all NSX Edge Nodes Successfully"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Set-NsxtEdgeNodeAuthenticationPolicy

##########################################  E N D   O F   F U N C T I O N S  ##########################################
#######################################################################################################################

################################################################################################################
##############  S I T E  P R O T E C T I O N  &  R E C O V E R Y   F U N C T I O N S   ##############

Function Install-SiteRecoveryManager {
    <#
		.SYNOPSIS
    	Deploy Site Recovery Manager Virtual Appliance

    	.DESCRIPTION
    	The Install-SiteRecoveryManager cmdlet deploys the Site Recovery Manager Virtual Appliance OVA. 
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values to retrive the management domain 
        vCenter Server details from its inventory and then:
        - Gathers vSphere configuration from vCenter Server
        - Gathers DNS and NTP configuration from SDDC Manager
        - Deploys the Site Recovery Manage Virtual Appliance

    	.EXAMPLE
    	Install-SiteRecoveryManager -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -srmFqdn sfo-wsa01.sfo.rainpole.io -srmIpAddress 192.168.31.60 -srmGateway 192.168.31.1 -srmSubnetMask 255.255.255.0 -srmOvfPath F:\identity-manager.ova -srmFolder sfo-m01-fd-srm
        This example deploys the Site Recovery Manager Virtual Appliance into the sfo-m01-fd-srm folder of the management domain
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$srmFqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$srmIpAddress,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$srmGateway,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$srmNetPrefix,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$srmNetworkSearchPath,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$srmFolder,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$srmOvfPath,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$srmVaRootPassword,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$srmVaAdminPassword,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$srmDbPassword,
        [Parameter (Mandatory = $false)] [ValidateSet("Standard", "Large")] [String]$deploymentOption
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("srmOvfPath")) {
            $srmOvfPath = Get-ExternalFileName -title "Select the Site Recovery Manager OVF file (.ovf)" -fileType "ovf"
        }
        else {
            if (!(Test-Path -Path $srmOvfPath)) {
                Write-Error  "Site Recovery Manager OVA '$srmOvfPath' File Not Found"
                Break
            }
        }
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
        $srmHostname = $srmFqdn.Split(".")[0]
        $srmDomain = $srmFQDN.Substring($srmFQDN.IndexOf(".") + 1)
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            $srmExists = Get-VM -Name $srmHostname -ErrorAction SilentlyContinue
            if ($srmExists) {
                Write-Warning "A virtual machine called $srmHostname already exists in vCenter Server $vcServer"
            }
            else {
                $dnsServer1 = (Get-VCFConfigurationDNS | Where-Object { $_.isPrimary -Match "True" }).ipAddress
                $dnsServer2 = (Get-VCFConfigurationDNS | Where-Object { $_.isPrimary -Match "False" }).ipAddress
                $cluster = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }).clusters.id) }).Name
                $datastore = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }).clusters.id) }).primaryDatastoreName
                $datacenter = (Get-Datacenter -Cluster $cluster).Name
                $mgmtPortgroup = ((get-vmhost)[0] | Get-VMHostNetwork | Select Hostname, VMkernelGateway -ExpandProperty VirtualNic | where-object {$_.DeviceName -eq "vmk0"}).PortGroupName
                $ntpServer = (Get-VCFConfigurationNTP).ipAddress
                $netMode = "static"
                $command = '"C:\Program Files\VMware\VMware OVF Tool\ovftool.exe" --noSSLVerify --acceptAllEulas  --allowAllExtraConfig --diskMode=thin --powerOn --name=' + $srmHostname + ' --ipProtocol="IPv4" --ipAllocationPolicy="fixedAllocatedPolicy" --vmFolder=' + $srmFolder + ' --net:"Network 1"=' + $mgmtPortgroup + '  --datastore=' + $datastore + ' --deploymentOption=' + $deploymentOption + ' --prop:varoot-password=' + $srmVaRootPassword + ' --prop:vaadmin-password=' + $srmVaAdminPassword +' --prop:dbpassword=' + $srmDbPassword + ' --prop:network.netmode.VMware_Site_Recovery_Manager_Appliance=' + $netMode + ' --prop:network.ip0.VMware_Site_Recovery_Manager_Appliance=' + $srmIpAddress + ' --prop:network.netprefix0.VMware_Site_Recovery_Manager_Appliance=' + $srmNetPrefix + ' --prop:vami.hostname=' + $srmFqdn + ' --prop:network.domain.VMware_Site_Recovery_Manager_Appliance=' + $srmDomain + ' --prop:network.searchpath.VMware_Site_Recovery_Manager_Appliance=' + $srmNetworkSearchPath + ' --prop:ntpserver=' + $ntpServer +' --prop:network.gateway.VMware_Site_Recovery_Manager_Appliance=' + $srmGateway + ' --prop:network.DNS.VMware_Site_Recovery_Manager_Appliance=' + $dnsServer1 + ',' + $dnsServer2 + '  --prop:enableFileIntegrity= ' + $enableFileIntegrity +' ' + $srmOvfPath + '  "vi://' + $vcenter.ssoAdmin + ':' + $vcenter.ssoAdminPass + '@' + $vcenter.fqdn + '/' + $datacenter + '/host/' + $cluster + '/"'
                Invoke-Expression "& $command"
                $srmExists = Get-VM -Name $srmHostname -ErrorAction SilentlyContinue
                if ($srmExists) {
                    $Timeout = 900  ## seconds
                    $CheckEvery = 15  ## seconds
                    Try {
                        $timer = [Diagnostics.Stopwatch]::StartNew()  ## Start the timer
                        Write-Output "Waiting for $srmIpAddress to become pingable."
                        While (!(Test-NetConnection $srmIpAddress -Port 5480 -WarningAction silentlyContinue | ? { $_.TcpTestSucceeded -eq $True })) {
                            ## If the timer has waited greater than or equal to the timeout, throw an exception exiting the loop
                            if ($timer.Elapsed.TotalSeconds -ge $Timeout) {
                                Throw "Timeout Exceeded. Giving up on ping availability to $srmIpAddress"
                            }
                            Start-Sleep -Seconds $CheckEvery  ## Stop the loop every $CheckEvery seconds
                        }
                    }
                    Catch {
                        Write-Error "Failed to get a Response from $srmFqdn"
                    }
                    Finally {
                        $timer.Stop()  ## Stop the timer
                        Write-Output "$srmHostname Deployed Successfully"
                    }
                }
            Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue
            }
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Install-SiteRecoveryManager

Function Install-vSphereReplicationManager {
    <#
		.SYNOPSIS
    	Deploy vSphere Replication Manager Virtual Appliance

    	.DESCRIPTION
    	The Install-vSphereReplicationManager cmdlet deploys the vSphere Replication Manager Virtual Appliance OVA. 
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values to retrive the management domain 
        vCenter Server details from its inventory and then:
        - Gathers vSphere configuration from vCenter Server
        - Gathers DNS and NTP configuration from SDDC Manager
        - Deploys the vSphere Replication Manager Virtual Appliance

    	.EXAMPLE
    	Install-vSphereReplicationManager -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -vrmsFqdn sfo-m01-vrms01.sfo.rainpole.io -vrmsIpAddress 192.168.31.60 -vrmsGateway 192.168.31.1 -vrmsSubnetMask 255.255.255.0 -vrmsOvfPath F:\vrms.ova -vrmsFolder sfo-m01-fd-vrms
        This example deploys the vSphere Replication Manager Virtual Appliance into the sfo-m01-fd-vrms folder of the management domain
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vrmsFqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vrmsIpAddress,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vrmsGateway,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vrmsNetPrefix,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vrmsNetworkSearchPath,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vrmsFolder,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$vrmsOvfPath,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$vrmsVaRootPassword,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$vrmsVaAdminPassword
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("vrmsOvfPath")) {
            $vrmsOvfPath = Get-ExternalFileName -title "Select the vSphere Replication Manager OVF file (.ovf)" -fileType "ovf"
        }
        else {
            if (!(Test-Path -Path $vrmsOvfPath)) {
                Write-Error  "vSphere Replication Manager OVA '$vrmsOvfPath' File Not Found"
                Break
            }
        }
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
        $vrmsHostname = $vrmsFqdn.Split(".")[0]
        $vrmsDomain = $vrmsFQDN.Substring($vrmsFQDN.IndexOf(".") + 1)
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            $vrmsExists = Get-VM -Name $vrmsHostname -ErrorAction SilentlyContinue
            if ($vrmsExists) {
                Write-Warning "A virtual machine called $vrmsHostname already exists in vCenter Server $vcServer"
            }
            else {
                $dnsServer1 = (Get-VCFConfigurationDNS | Where-Object { $_.isPrimary -Match "True" }).ipAddress
                $dnsServer2 = (Get-VCFConfigurationDNS | Where-Object { $_.isPrimary -Match "False" }).ipAddress
                $cluster = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }).clusters.id) }).Name
                $datastore = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }).clusters.id) }).primaryDatastoreName
                $datacenter = (Get-Datacenter -Cluster $cluster).Name
                $mgmtPortgroup = ((get-vmhost)[0] | Get-VMHostNetwork | Select Hostname, VMkernelGateway -ExpandProperty VirtualNic | where-object {$_.DeviceName -eq "vmk0"}).PortGroupName
                $ntpServer = (Get-VCFConfigurationNTP).ipAddress
                $netMode = "static"
                $command = '"C:\Program Files\VMware\VMware OVF Tool\ovftool.exe" --noSSLVerify --acceptAllEulas  --allowAllExtraConfig --diskMode=thin --powerOn --name=' + $vrmsHostname + ' --ipProtocol="IPv4" --ipAllocationPolicy="fixedAllocatedPolicy" --vmFolder=' + $vrmsFolder + ' --net:"Network 1"=' + $mgmtPortgroup + '  --datastore=' + $datastore + ' --prop:varoot-password=' + $vrmsVaRootPassword + ' --prop:vaadmin-password=' + $vrmsVaAdminPassword +' --prop:network.netmode.vSphere_Replication_Appliance=' + $netMode + ' --prop:network.ip0.vSphere_Replication_Appliance=' + $vrmsIpAddress + ' --prop:network.netprefix0.vSphere_Replication_Appliance=' + $vrmsNetPrefix + ' --prop:vami.hostname=' + $vrmsFqdn + ' --prop:network.domain.vSphere_Replication_Appliance=' + $vrmsDomain + ' --prop:network.searchpath.vSphere_Replication_Appliance=' + $vrmsNetworkSearchPath + ' --prop:ntpserver=' + $ntpServer +' --prop:network.gateway.vSphere_Replication_Appliance=' + $vrmsGateway + ' --prop:network.DNS.vSphere_Replication_Appliance=' + $dnsServer1 + ',' + $dnsServer2 + '  --prop:enableFileIntegrity= ' + $enableFileIntegrity +' --vService:installation=com.vmware.vim.vsm:extension_vservice ' + $vrmsOvfPath + '  "vi://' + $vcenter.ssoAdmin + ':' + $vcenter.ssoAdminPass + '@' + $vcenter.fqdn + '/' + $datacenter + '/host/' + $cluster + '/"'
                Invoke-Expression "& $command"
                $vrmsExists = Get-VM -Name $vrmsHostname -ErrorAction SilentlyContinue
                if ($vrmsExists) {
                    $Timeout = 900  ## seconds
                    $CheckEvery = 15  ## seconds
                    Try {
                        $timer = [Diagnostics.Stopwatch]::StartNew()  ## Start the timer
                        Write-Output "Waiting for $vrmsIpAddress to become pingable."
                        While (!(Test-NetConnection $vrmsIpAddress -Port 5480 -WarningAction silentlyContinue | ? { $_.TcpTestSucceeded -eq $True })) {
                        ## If the timer has waited greater than or equal to the timeout, throw an exception exiting the loop
                        if ($timer.Elapsed.TotalSeconds -ge $Timeout) {
                            Throw "Timeout Exceeded. Giving up on ping availability to $vrmsIpAddress"
                        }
                        Start-Sleep -Seconds $CheckEvery  ## Stop the loop every $CheckEvery seconds
                        }
                    }
                    Catch {
                        Write-Error "Failed to get a Response from $vrmsFqdn"
                    }
                    Finally {
                        $timer.Stop()  ## Stop the timer
                        Write-Output "$vrmsHostname Deployed Successfully"
                    }       
                }
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue
            }
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}

Export-ModuleMember -Function Install-vSphereReplicationManager

Function Connect-DRSolutionTovCenter {
    <#
		.SYNOPSIS
    	Register SRM & vRMS with vCenter

    	.DESCRIPTION
    	The Connect-DRSolutionTovCenter cmdlet deploys the Site Recovery Manage Virtual Appliance OVA. 
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values to retrive the management domain 
        vCenter Server details from its inventory and then:
        - Gathers vSphere configuration from vCenter Server
        - Gathers DNS and NTP configuration from SDDC Manager
        - Deploys the Site Recovery Manage Virtual Appliance

    	.EXAMPLE
    	Connect-DRSolutionTovCenter -solution SRM -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -applianceFqdn sfo-m01-srm01.sfo.rainpole.io -vamiAdminPassword 'VMw@re1!' -domainType MANAGEMENT -siteName SFO01 -ssoAdminUser administrator@vsphere.local -ssoAdminPassword 'VMw@re1!' -adminEmail 'admin@rainpole.io'
        This example registers Site Recovery Manager with the vCenter Server of the management domain
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,        
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$applianceFqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vamiAdminPassword,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$siteName,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ssoAdminUser,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ssoAdminPassword,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$adminEmail,
        [Parameter (Mandatory = $true)] [ValidateSet("SRM", "VRMS")] [String]$solution
    )

    $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
    if ($solution -eq "SRM") {
        $extensionKey = "com.vmware.vcDr"
    }
    else {
        $extensionKey = "com.vmware.vcHms"
    }
    Try {
        # Retireve the vCenter SSL Thumbprint
        $vcenterFQDN = $vcenter.fqdn
        $command = 'openssl s_client -connect ' + $vcenterFQDN + ':443 2>&1 | openssl x509 -sha256 -fingerprint -noout'
        $thumbprint = (iex "& $command").Split("=")[1]
        $vCenterInstanceUuid = Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Select-Object InstanceUuid
        $vCenterInstanceUuid = $vCenterInstanceUuid.InstanceUuid
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue

        # Register Site Recovery Manager with vCenter
        $response = Register-DRSolutionTovCenter -applianceFqdn $applianceFqdn -vamiAdminPassword $vamiAdminPassword -pscHost $vcenterFQDN -thumbprint $thumbprint -vcInstanceId $vCenterInstanceUuid -ssoAdminUser $ssoAdminUser -ssoAdminPassword $ssoAdminPassword -siteName $siteName -adminEmail $adminEmail -hostName $applianceFqdn -extensionKey $extensionKey
        $validateRegistration = Get-DRSolutionSummary -fqdn $applianceFqdn -username admin -password $vamiAdminPassword
        if ($validateRegistration.data.drConfiguration.vcName -eq $vcenterFQDN) {
            Write-output "Successfully Registered $solution instance $applianceFqdn to vCenter Server $vcenterFQDN"
        }
        else {
            Write-Output "Something went wrong"
        }
    }              
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Connect-DRSolutionTovCenter

Function Install-VAMICertificate {
    <#
		.SYNOPSIS
    	Install a Signed Certificate Using VAMI Appliance interface

    	.DESCRIPTION
    	The Install-VAMICertificate cmdlet replaces the certificate on the Site Recovery Manager appliance

    	.EXAMPLE
    	Install-VAMICertificate -fqdn sfo-m01-srm01.sfo.rainpole.io -username admin -password VMw@re1! -certFile C:\Certs\sfo-m01-srm01.4.p12 -certPassword VMw@re1!
        This example configures the Site Recovery Manager Virtual Appliance with the with a signed cert
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$certFile,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$certPassword
    )

    Try {
        
        if (!$PsBoundParameters.ContainsKey("certFile")) {
            $certFile = Get-ExternalFileName -title "Select the Appliance Certificate File (.p12)" -fileType "p12"
        }
        elseif ($PsBoundParameters.ContainsKey("certFile")) {
            if (!(Test-Path -Path $certFile)) {
                Write-Error  "Certificate (.p12) '$certFile' File Not Found"
            }
        }
        Try {
            $base64string = [Convert]::ToBase64String([IO.File]::ReadAllBytes($certFile))
            $body = '{
                "certificateContent": "'+$base64string+'",
                "certificatePassword": "'+$certPassword+'"
              }'
            $sessionId = Request-VAMISessionId -fqdn $fqdn -username $username -password $password
            $VAMIAuthHeaders = createVAMIAuthHeader($sessionId)                    
            $uri = "https://"+$fqdn+":5480/configure/requestHandlers/installPkcs12Certificate"
            $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $VAMIAuthheaders -body $body
            #$response
        }
        Catch {
            #TODO - Write function to query cert Thumbprint and compare to installed cert
            #Debug-ExceptionWriter -object $_
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Install-VAMICertificate

Function Get-DRSolutionSummary {
    <#
		.SYNOPSIS
    	Retrieves the Site Recovery Manager summary

    	.DESCRIPTION
    	The Get-DRSolutionSummary cmdlet retrieves the Site Recovery Manager summary

    	.EXAMPLE
    	Get-DRSolutionSummary -fqdn sfo-m01-srm01.sfo.rainpole.io -username admin -password VMw@re1!
        This example retrieves the Site Recovery Manager summary
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password
    )

    Try {
        $sessionId = Request-VAMISessionId -fqdn $fqdn -username $username -password $password
        $VAMIAuthHeaders = createVAMIAuthHeader($sessionId)                    
        $uri = "https://"+$fqdn+":5480/configure/requestHandlers/getSummaryInfo"
        $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $VAMIAuthheaders -body $body
        $response
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}    
Export-ModuleMember -Function Get-DRSolutionSummary

Function Register-DRSolutionTovCenter {
    <#
		.SYNOPSIS
    	Registers SRM & vRMS with a given vCenter Server

    	.DESCRIPTION
    	The Register-DRSolutionTovCenter cmdlet registers SRM & vRMS with a given vCenter Server

    	.EXAMPLE
    	Register-DRSolutionTovCenter -applianceFqdn sfo-m01-srm01.sfo.rainpole.io -vamiAdminPassword VMw@re1! -pscHost sfo-m01-vc01.sfo.rainpole.io -thumbprint EA:0F:24:7E:B4:4C:5E:ED:38:AE:79:A6:9E:A2:E8:8F:EE:54:D8:AF:18:6A:A2:57:DC:87:09:68:D4:76:36:DD -vcInstanceId 53cad28c-4160-4956-b7c1-c7bbc5185a39 -ssoAdminUser administrator@vsphere.local -ssoAdminPassword VMw@re1! -siteName SFO01 -adminEmail admin@rainpole.io -hostName sfo-m01-srm01.sfo.rainpole.io
        This example registers the Site Recovery Manager Virtual Appliance with vCenter
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$applianceFqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vamiAdminPassword,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pscHost,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$thumbprint,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vcInstanceId,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ssoAdminUser,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ssoAdminPassword,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$siteName,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$adminEmail,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$hostName,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$extensionKey
    )

    Try {
        $body = '{
            "connection": {
                "pscHost": "'+$pscHost+'",
                "pscPort": 443,
                "thumbprint": "'+$thumbprint+'",
                "vcInstanceId": "'+$vcInstanceId+'",
                "vcThumbprint": "'+$thumbprint+'"
            },
            "adminUser": "'+$ssoAdminUser+'",
            "adminPassword": "'+$ssoAdminPassword+'",
            "siteName": "'+$siteName+'",
            "adminEmail": "'+$adminEmail+'",
            "hostName": "'+$hostName+'",
            "extensionKey": "'+$extensionKey+'"
        }'
        $body
        $sessionId = Request-VAMISessionId -fqdn $applianceFqdn -username admin -password $vamiAdminPassword
        $VAMIAuthHeaders = createVAMIAuthHeader($sessionId)                    
        $uri = "https://"+$applianceFqdn+":5480/configure/requestHandlers/configureAppliance"
        $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $VAMIAuthheaders -body $body
        $response

        }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Register-DRSolutionTovCenter

Function Backup-VMOvfProperties {
    <#
		.SYNOPSIS
    	Backup-VMOvfProperties

    	.DESCRIPTION
    	The Backup-VMOvfProperties cmdlet creates a backup of the OVF properties for each supplied VM. 
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values to retrive the DR protected VMs from its inventory and then:
        - Creates a backup of the VM OVF environment

    	.EXAMPLE
    	Backup-VMOvfProperties -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1!
        This example creates a backup of the OVF properties for each supplied VM.
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$fileDir
    )
        
    Try {
        if (!$PsBoundParameters.ContainsKey("fileDir")) {
            $fileDir = Get-ExternalDirectoryPath
        }
        else {
            if (!(Test-Path -Path $fileDir)) {
                Write-Error  "Directory '$fileDir' Not Found"
                Break
            }
        } 
        # Disconnect all connected vCenters to ensure only the desired vCenter is available
        if ($defaultviservers) {
            $server = $defaultviservers.Name
            foreach ($server in $defaultviservers) {            
                Disconnect-VIServer -Server $server -Confirm:$False
            }
        }
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domainType MANAGEMENT
        # Retrieve vRSLCM VM Name
        $vrslcmDetails = Get-vRSLCMServerDetail -fqdn $server -username $user -password $pass
        if ($vrslcmDetails) {
            Write-Output "Getting vRealize Suite Lifecycle Manager VM Name"
            Connect-VIServer -server $vcenter.fqdn -user $vcenter.ssoAdmin -password $vcenter.ssoAdminPass | Out-Null
            $vrslcmVMName = Get-VM * | Where-Object {$_.Guest.Hostname -eq $vrslcmDetails.fqdn} | Select-Object Name
            $vrslcmVMName = $vrslcmVMName.Name
            $vmsToBackup = @("$vrslcmVMName")                
            Disconnect-VIServer -server $vcenter.fqdn -Confirm:$False
        }
        # Retrieve WSA VM Names
        $wsaDetails = Get-WSAServerDetail -fqdn $server -username $user -password $pass
        if ($wsaDetails) {
            Write-Output "Getting Workspace ONE Access VM Names"
            Connect-VIServer -server $vcenter.fqdn -user $vcenter.ssoAdmin -password $vcenter.ssoAdminPass | Out-Null
            Foreach ($wsaFQDN in $wsaDetails.fqdn) {
                $wsaVMName = Get-VM * | Where-Object {$_.Guest.Hostname -eq $wsaFQDN} | Select-Object Name
                $wsaVMName = $wsaVMName.Name
                $vmsToBackup += ,$wsaVMName
            }
            Disconnect-VIServer -server $vcenter.fqdn -Confirm:$False
        }
        # Retrieve vROPs VM Names
        $vropsDetails = Get-vROPsServerDetail -fqdn $server -username $user -password $pass
        if ($vropsDetails) {
            Write-Output "Getting vRealize Operations Manager VM Names"
            Connect-VIServer -server $vcenter.fqdn -user $vcenter.ssoAdmin -password $vcenter.ssoAdminPass | Out-Null
            Foreach ($vropsFQDN in $vropsDetails.fqdn) {
                $vropsVMName = Get-VM * | Where-Object{$_.Guest.Hostname -eq $vropsFQDN} | Select-Object Name
                $vropsVMName = $vropsVMName.Name
                $vmsToBackup += ,$vropsVMName
            }
            Disconnect-VIServer -server $vcenter.fqdn -Confirm:$False
        }
        # Retrieve vRA VM Names
        $vraDetails = Get-vRAServerDetail -fqdn $server -username $user -password $pass
        if ($vraDetails) {
            Write-Output "Getting vRealize Automation VM Names"
            Connect-VIServer -server $vcenter.fqdn -user $vcenter.ssoAdmin -password $vcenter.ssoAdminPass | Out-Null
            Foreach ($vraFQDN in $vraDetails.fqdn) {
                $vraVMName = Get-VM * | Where-Object {$_.Guest.Hostname -eq $vraFQDN} | Select-Object Name
                $vraVMName = $vraVMName.Name
                $vmsToBackup += ,$vraVMName
            }
            Disconnect-VIServer -server $vcenter.fqdn -Confirm:$False
        }
        Connect-VIServer -server $vcenter.fqdn -user $vcenter.ssoAdmin -password $vcenter.ssoAdminPass | Out-Null
        Foreach ($vm in $vmsToBackup) {
            $vmToBackup = Get-VM -Name $vm
            Get-VMvAppConfig -vm $vmToBackup
        }
        Disconnect-VIServer -server $vcenter.fqdn -Confirm:$False
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Backup-VMOvfProperties

Function Restore-VMOvfProperties {
    <#
		.SYNOPSIS
    	Restore-VMOvfProperties

    	.DESCRIPTION
    	The Restore-VMOvfProperties cmdlet creates a backup of the OVF properties for each supplied VM. 
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values to retrive the DR protected VMs from its inventory and then:
        - Creates a restore of the VM OVF environment

    	.EXAMPLE
    	Restore-VMOvfProperties -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1!
        This example creates a backup of the OVF properties for each supplied VM.
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$fileDir
    )
  
    Try {       
        if (!$PsBoundParameters.ContainsKey("fileDir")) {
            $fileDir = Get-ExternalDirectoryPath
        }
        else {
            if (!(Test-Path -Path $fileDir)) {
                Write-Error  "Directory '$fileDir' Not Found"
                Break
            }
        } 
        $fileNames = @()
        $fileNames = Get-ChildItem -File "$($fileDir)\*-property-backup.json" -Recurse
        # Disconnect all connected vCenters to ensure only the desired vCenter is available
        if ($defaultviservers) {
            $server = $defaultviservers.Name
            foreach ($server in $defaultviservers) {            
                Disconnect-VIServer -Server $server -Confirm:$False
            }
        }
        $vCenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domainType MANAGEMENT
        Connect-VIServer -server $vcenter.fqdn -user $vcenter.ssoAdmin -password $vcenter.ssoAdminPass | Out-Null
        Foreach ($fileName in $fileNames) {
            $fileName = $fileName.Name
            $separator = "-property-backup.json"
            $restoredVM = ($filename -split $separator)[0]

            $vmSettings = Get-content "$($fileDir)\$($restoredVM)-property-backup.json" | convertfrom-json
            if ($vmSettings) {
                $foundVM = Get-VM -Name $restoredVM -ErrorAction SilentlyContinue
                if ($foundVM) {
                    Write-Output "Restoring VM OVF Settings for $restoredVM"
                    Set-VMOvfIPAssignment -vm $foundVM -assignment $vmSettings.IpAssignment
                    if ($vmSettings.eula) {
                        Set-VMOvfEULA -vm $foundVM -eula $vmSettings.eula    
                    }
                    Set-VMOvfEnvTransport -vm $foundVM -transport $vmSettings.ovfEnvironmentTransport
                    foreach ($product in $vmSettings.product) {
                        New-VMOvfProduct -vm $foundVM -product $product
                    }
                    foreach ($property in $vmSettings.property) {
                        New-VMOvfProperty -vm $foundVM -property $property
                    }                   
                }
                else {
                    Write-Output "Placeholder $restoredVM not found in $($vcenter.fqdn)"
                }
            }
        }
        Disconnect-VIServer -server $vcenter.fqdn -Confirm:$False
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Restore-VMOVFProperties

Function Get-VMvAppConfig
{
    <#
        .SYNOPSIS
        Retrieves the full OVF environment settings from a standard VM.

        .DESCRIPTION
        Saves the setting of the passed VM object to a JSON file

        .EXAMPLE
        Get-VMAppConfig -vm $vm
    #>
    Param (
        [Parameter (Mandatory=$true)] [PSObject]$vm
    )

    $targetFile = $fileDir + "\" + $vm.name + "-property-backup.json"
    Write-Output "Initating Backup of OVF Properties for $vm"
    Try {
        if ($vm.ExtensionData.Config.VAppConfig) {
            $vmVappConfig = $vm.ExtensionData.Config.VAppConfig | ConvertTo-Json | Out-File $targetFile
            Write-Output "OVF Properties successfully captured"
            return $vmVappConfig
        }
        else {
            Write-Output "No OVF properties were detected on $($vm.name). You may ignore this message if this is correct." -colour magenta
        }
    }
    Catch
    {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Get-VMvAppConfig

Function New-VMOvfProperty
{
    <#
       .SYNOPSIS
        Create a single OVF Property on a standard VM.

        .DESCRIPTION
        Accepts a object with propery details, parses it and adds it to supplied VM

        .EXAMPLE
        New-VMOvfProperty -vm $vm -property $propertyObject
    #>

    Param (
        [Parameter (Mandatory=$true)] [PSObject]$vm,
        [Parameter (Mandatory=$true)] [PSObject]$property
    )

    #define spec
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec
    $propertySpec = New-Object VMware.Vim.VAppPropertySpec
    
    #populate spec
    $propertySpec.Operation = "Add"
    $propertySpec.Info = New-Object VMware.Vim.VAppPropertyInfo
    $propertySpec.info.category = $property.category 
    $propertySpec.info.classId = $property.classId
    $propertySpec.info.defaultValue = $property.defaultValue 
    $propertySpec.info.description = $property.description   
    $propertySpec.info.id = $property.id 
    $propertySpec.info.instanceId = $property.instanceId      
    $propertySpec.info.key = $property.key
    $propertySpec.info.label = $property.label   
    $propertySpec.info.type = $property.type 
    $propertySpec.info.typeReference = $property.typeReference 
    $propertySpec.info.userConfigurable = $property.userConfigurable 
    $propertySpec.info.value = $property.value
    $spec.VAppConfig.Property = $propertySpec

    #write spec
    Write-Output "Creating OVF Property $($property.id) on $($vm.name)"
    $task = $vm.ExtensionData.ReconfigVM_Task($spec)
    $task1 = Get-Task -Id ("Task-$($task.value)")
    $waitask = $task1 | Wait-Task 
}
Export-ModuleMember -Function New-VMOvfProperty

Function Set-VMOvfIPAssignment
{
    <#
        .SYNOPSIS
        Sets the IP Assignment OVF Setting

        .DESCRIPTION
        Accepts a object with IP Assigment details and assigns it to the supplied VM

        .EXAMPLE
        Set-VMOvfIPAssignment -vm $vm -assignment $assignmentObject

    #>    
    Param (
        [Parameter (Mandatory=$true)] [PSObject]$vm,
        [Parameter (Mandatory=$true)] [PSObject]$assignment
    )
    
    #define spec
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec
    $assignmentSpec = New-Object VMware.Vim.VAppIPAssignmentInfo

    #populate spec
    $assignmentSpec.ipAllocationPolicy = $assignment.ipAllocationPolicy
    $assignmentSpec.SupportedAllocationScheme = $assignment.SupportedAllocationScheme
    $assignmentSpec.SupportedIpProtocol = $assignment.SupportedIpProtocol
    $assignmentSpec.IpProtocol = $assignment.IpProtocol
    $spec.vAppConfig.IpAssignment = $assignmentSpec

    #write spec
    Write-Output "Configuring IP Assignment setting on $($vm.name)"
    $task = $vm.ExtensionData.ReconfigVM_Task($spec)
    $task1 = Get-Task -Id ("Task-$($task.value)")
    $waitask = $task1 | Wait-Task 
}
Export-ModuleMember -Function Set-VMOvfIPAssignment

Function Set-VMOvfEnvTransport
{
    <#
        .SYNOPSIS
        Sets the Environment Transport setting for OVF properties

        .DESCRIPTION
        Accepts a object with Environment Transport details and assigns it to the supplied VM

        .EXAMPLE
        Set-VMOvfEnvTransport -vm $vm -transport $transportObject

    #> 

    Param (
        [Parameter (Mandatory=$true)] [PSObject]$vm,
        [Parameter (Mandatory=$true)] [PSObject]$transport
    )

    #define spec
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec

    #populate spec
    $spec.vAppConfig.ovfEnvironmentTransport = $transport
    
    #write spec
    Write-Output "Configuring Environment Transport setting on $($vm.name)"
    $task = $vm.ExtensionData.ReconfigVM_Task($spec)
    $task1 = Get-Task -Id ("Task-$($task.value)")
    $waitask = $task1 | Wait-Task 
}
Export-ModuleMember -Function Set-VMOvfEnvTransport

Function New-VMOvfProduct
{
    <#
        .SYNOPSIS
        Create a single OVF Product on a standard VM.

        .DESCRIPTION
        Accepts a object with produt details, parses it and adds it to supplied VM

        .EXAMPLE
        New-VMOvfProduct -vm $vm -product $productObject

    #>

    Param (
        [Parameter (Mandatory=$true)] [PSObject]$vm,
        [Parameter (Mandatory=$true)] [PSObject]$product
    )

    #define spec
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec
    $productSpec = New-Object VMware.Vim.VAppProductSpec

    #populate spec
    $productSpec.Operation = "Add"
    $productSpec.Info = New-Object VMware.Vim.VAppProductInfo
    $productSpec.info.appUrl = $product.appUrl
    $productSpec.info.classId = $product.classId 
    $productSpec.info.fullVersion = $product.fullVersion 
    $productSpec.info.instanceId = $product.instanceId   
    $productSpec.info.key = $product.key 
    $productSpec.info.name = $product.name 
    $productSpec.info.productUrl = $product.productUrl   
    $productSpec.info.vendor = $product.vendor
    $productSpec.info.vendorUrl = $product.vendorUrl
    $productSpec.info.version = $product.version
    $spec.VAppConfig.Product = $productSpec

    #write spec
    Write-Output "Adding Product Setting on $($vm.name)"
    $task = $vm.ExtensionData.ReconfigVM_Task($spec)
    $task1 = Get-Task -Id ("Task-$($task.value)")
    $waitask = $task1 | Wait-Task 
}
Export-ModuleMember -Function New-VMOvfProduct

Function Set-VMOvfEULA
{
    <#
        .SYNOPSIS
        Sets the EULA setting for OVF properties

        .DESCRIPTION
        Accepts a object with EULA details and assigns it to the supplied VM

        .EXAMPLE
        Set-VMOvfEULA -vm $vm -eula $eulaObject
    #>    

    Param (
        [Parameter (Mandatory=$true)] [PSObject]$vm,
        [Parameter(Mandatory=$true)] [PSObject]$eula
    )

    #define spec
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec

    #populate spec
    $spec.vAppConfig.eula = $eula

    #write spec
    Write-Output "Setting EULA on $($vm.name)"
    $task = $vm.ExtensionData.ReconfigVM_Task($spec)
    $task1 = Get-Task -Id ("Task-$($task.value)")
    $waitask = $task1 | Wait-Task 
}
Export-ModuleMember -Function Set-VMOvfEULA

Function Get-NSXLBDetails {
    <#
		.SYNOPSIS
    	Get-NSXLBDetails

    	.DESCRIPTION
    	The Get-NSXLBDetails cmdlet gets the IP addresses of the VIPs & pool members for the NSX-T Load Balancer for vRealize. 
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values to retrive the NSX load balancer configurationn

    	.EXAMPLE
    	Get-NSXLBDetails -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1!
        This example gets the IP addresses of the VIPs & pool members for the NSX-T Load Balancer for vRealize.
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass
    )
  
    Try {
        # Retrieve WSA VIP
        $wsaDetails = Get-WSAServerDetail -fqdn $server -username $user -password $pass
        if ($wsaDetails) {
            Write-Output "Found Workspace ONE Access. Getting Virtual Server & Node IPs"
                $wsaVIP = $wsaDetails.loadBalancerIpAddress
                $wsaNode1IP = $wsaDetails.node1IpAddress
                $wsaNode2IP = $wsaDetails.node2IpAddress
                $wsaNode3IP = $wsaDetails.node3IpAddress
            }
        # Retrieve vROPs VM Names
        $vropsDetails = Get-vROPsServerDetail -fqdn $server -username $user -password $pass
        if ($vropsDetails) {
            Write-Output "Found vRealize Operations. Getting Virtual Server & Node IPs"                
                $vropsVIP = $vropsDetails.loadBalancerIpAddress
                $vopsNode1IP = $vropsDetails.node1IpAddress
                $vopsNode2IP = $vropsDetails.node2IpAddress
                $vopsNode3IP = $vropsDetails.node3IpAddress
            }
        # Retrieve vRA VM Names
        $vraDetails = Get-vRAServerDetail -fqdn $server -username $user -password $pass
        if ($vraDetails) {
            Write-Output "Found vRealize Automation. Getting Virtual Server & Node IPs"
                $vraVIP = $vraDetails.loadBalancerIpAddress
                $vraNode1IP = $vraDetails.node1IpAddress
                $vraNode2IP = $vraDetails.node2IpAddress
                $vraNode3IP = $vraDetails.node3IpAddress
        }
        # Gather NSX-T Manager Details
        Write-Output "Getting NSX-T Login Details"
        $nsxt = Get-NsxtServerDetail -fqdn $server -user $user -pass $pass -domainType MANAGEMENT
        $nsxtFQDN = $nsxt.fqdn
                
    } 
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Get-NSXLBDetails

#######################################################################################################################
##################  D E V E L O P E R   R E A D Y   I N F R A S T R U C T U R E   F U N C T I O N S   #################

Function Add-NetworkSegment {
    <#
        .SYNOPSIS
        Create an NSX segment

        .DESCRIPTION
        The Add-NetworkSegment cmdlet creates an NSX Segment

        .EXAMPLE
        Add-NetworkSegment -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-w01 -segmentName "sfo-w01-kub-seg01" -gatewayType "Tier1" -connectedGateway "sfo-w01-ec01-t1-gw01" -cidr "192.168.31.1/24" -transportZone "overlay-tz-sfo-w01-nsx01.sfo.rainpole.io" -segmentType Overlay
        This example creates an overlay-backed NSX segment in the workload domain sfo-w01
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$segmentName,
        [Parameter (Mandatory = $true)] [String]$connectedGateway,
        [Parameter (Mandatory = $true)] [String]$cidr,
        [Parameter (Mandatory = $true)] [String]$transportZone,
        [Parameter (Mandatory = $true)] [ValidateSet("Tier0", "Tier1")] [String]$gatewayType,
        [Parameter (Mandatory = $true)] [ValidateSet("Overlay", "VLAN")] [String]$segmentType
    )

    Try {
        $nsxtManagerDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain
        Request-NsxToken -fqdn $nsxtManagerDetails.fqdn -username $nsxtManagerDetails.adminUser -password $nsxtManagerDetails.adminPass | Out-Null
        if (!($validateSegment = Get-NsxtSegment -name $segmentName)) {
            if ($gatewayType -eq "Tier0") { $tierGatewayExists = Get-NsxtTier0Gateway -name $connectedGateway }
            if ($gatewayType -eq "Tier1") { $tierGatewayExists = Get-NsxtTier1Gateway -name $connectedGateway }
            if ($tierGatewayExists) {
                $validateTransportZone = Get-NsxtTransportZone -Name $transportZone -ErrorAction SilentlyContinue
                if ($validateTransportZone.display_name -eq $transportZone) {
                    if ($validateTransportZone.transport_type -ne $segmentType.ToUpper()){
                        Write-Error "NSX Transport Zone $transportZone does not match the defined segment Type $segmentType on NSX Manager $($nsxtManagerDetails.fqdn)"
                        Break
                    }
                }
                else {
                    Write-Error "NSX Transport Zone $transportZone was not found on NSX Manager $($nsxtManagerDetails.fqdn)"
                    Break
                }
                New-NsxtSegment -name $segmentName -connectedGateway $connectedGateway -cidr $cidr -transportZone $transportZone -gatewayType $gatewayType -segmentType $segmentType | Out-Null
                if ($validateSegment = Get-NsxtSegment -name $segmentName) {
                    Write-Output "Created NSX segment $segmentName on NSX Manager $($nsxtManagerDetails.fqdn) completed Succesfully"
                }
                else {
                    Write-Error "Creation of the NSX segment $segmentName on NSX Manager $($nsxtManagerDetails.fqdn) failed, please retry"
                }
            }
            else {
                Write-Error "NSX $gatewayType Gateway $connectedGateway does not exist on NSX Manager $($nsxtManagerDetails.fqdn)"
            }
        }
        else {
            Write-Warning "$segmentType-backed NSX segment $segmentName already exists on NSX Manager $($nsxtManagerDetails.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-NetworkSegment

Function Add-PrefixList {
    <#
        .SYNOPSIS
        Create an NSX Prefix List

        .DESCRIPTION
        The Add-PrefixList cmdlet creates an NSX Prefix List

        .EXAMPLE
        Add-PrefixList -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-w01 -tier0Gateway sfo-w01-ec01-t0-gw01 -prefixListName sfo-w01-ec01-t0-gw01-mgmt-prefixlist -subnetCIDR 192.168.20.0/24 -ingressSubnetCidr "192.168.21.0/24" -egressSubnetCidr "192.168.22.0/24" -GE "28" -LE "32" -action PERMIT
        This example creates an NSX Prefix List in the workload domain NSX Manager cluster
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$tier0Gateway,
        [Parameter (Mandatory = $true)] [String]$prefixListName,
        [Parameter (Mandatory = $true)] [String]$subnetCidr,
        [Parameter (Mandatory = $true)] [String]$ingressSubnetCidr,
        [Parameter (Mandatory = $true)] [String]$egressSubnetCidr,
        [Parameter (Mandatory = $false)] [String]$GE,
        [Parameter (Mandatory = $false)] [String]$LE,
        [Parameter (Mandatory = $true)] [ValidateSet("PERMIT", "DENY")] [String]$action
    )

    Try {
        $nsxtManagerDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain
        Request-NsxToken -fqdn $nsxtManagerDetails.fqdn -username $nsxtManagerDetails.adminUser -password $nsxtManagerDetails.AdminPass | Out-Null
        if ($tier0GatewayExists = Get-NsxtTier0Gateway -name $tier0Gateway) {
            if (!($checkPrefixList = Get-NsxtTier0Gateway -name $tier0Gateway | Get-NsxtPrefixList -name $prefixListName -ErrorAction SilentlyContinue)) {
                Get-NsxtTier0Gateway -name $tier0Gateway | New-NsxtPrefixList -name $prefixListName -subnetCidr $subnetCidr -action $action | Out-Null
                if ($checkPrefixList = Get-NsxtTier0Gateway -name $tier0Gateway | Get-NsxtPrefixList -name $prefixListName -ErrorAction SilentlyContinue) {
                    Get-NsxtTier0Gateway -name $tier0Gateway | Get-NsxtPrefixList -name $prefixListName | Add-NsxtPrefix -subnetCidr $ingressSubnetCidr -GE $GE -LE $LE -action $action | Out-Null
                    Get-NsxtTier0Gateway -name $tier0Gateway | Get-NsxtPrefixList -name $prefixListName | Add-NsxtPrefix -subnetCidr $egressSubnetCidr -GE $GE -LE $LE -action $action | Out-Null
                    Write-Output "NSX IP Prefix List $prefixListName created on NSX Manager $($nsxtManagerDetails.fqdn) Succesfully"
                }
                else {
                    Write-Error "NSX IP Prefix List $prefixListName creation on NSX Manager $($nsxtManagerDetails.fqdn) Failed"
                }
            }
            else {
                Write-Warning "NSX IP Prefix List $prefixListName already exists on NSX Manager $($nsxtManagerDetails.fqdn)"
            }
        }
        else {
            Write-Error "NSX Tier0 Gateway $tier0Gateway does not exist on NSX Manager $($nsxtManagerDetails.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-PrefixList

Function Add-RouteMap {
    <#
        .SYNOPSIS
        Create an NSX Route Map for use by VCF

        .DESCRIPTION
        The Add-RouteMap cmdlet creates an NSX Route Map

        .EXAMPLE
        Add-RouteMap -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-w01 -tier0Gateway sfo-w01-ec01-t0-gw01 -routeMapName sfo-w01-ec01-t0-gw01-routemap -prefixListName sfo-w01-ec01-t10-gw01-mgmt-prefixlist -action PERMIT -applyPolicy:$true
        This example creates an NSX Route Map in workload domain sfo-w01
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$tier0Gateway,
        [Parameter (Mandatory = $true)] [String]$routeMapName,
        [Parameter (Mandatory = $true)] [String]$prefixListName,
        [Parameter (Mandatory = $true)] [ValidateSet("PERMIT", "DENY")][String]$action,
        [Parameter (Mandatory = $true)] [Bool]$applyPolicy
    )

    Try {
        $nsxtManagerDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain
        Request-NsxToken -fqdn $nsxtManagerDetails.fqdn -username $nsxtManagerDetails.adminUser -password $nsxtManagerDetails.AdminPass | Out-Null
        if ($tier0GatewayExists = Get-NsxtTier0Gateway -name $tier0Gateway) {
            if (!($checkRouteMap = Get-NsxtRouteMap -tier0Gateway $tier0Gateway -name $routeMapName -ErrorAction SilentlyContinue)) {
                if ($checkPrefixList = Get-NsxtTier0Gateway -name $tier0Gateway | Get-NsxtPrefixList -name $prefixListName -ErrorAction SilentlyContinue) {
                    Get-NsxtTier0Gateway -name $tier0Gateway | New-NsxtRouteMap -name $routeMapName -prefixList $prefixListName -action $Action | Out-Null
                    if ($checkRouteMap = Get-NsxtRouteMap -tier0Gateway $tier0Gateway -name $routeMapName -ErrorAction SilentlyContinue) {
                        if ($applyPolicy -eq $true) {
                            Get-NsxtRouteRedistributionPolicy -tier0Gateway $tier0Gateway | Set-NsxtRouteRedistributionPolicy -routeMap $routeMapName | Out-Null
                        }
                        Write-OutPut "NSX Route Map $routeMapName created on NSX Manager $($nsxtManagerDetails.fqdn) Succesfully"
                    }
                    else {
                        Write-Error "NSX Route Map $routeMapName creation on NSX Manager $($nsxtManagerDetails.fqdn) Failed"
                    }
                }
                else {
                    Write-Error "NSX IP Prefix List $prefixListName does not exist on NSX Manager $($nsxtManagerDetails.fqdn)"
                }
            }
            else {
                Write-Warning "NSX Route Map $routeMapName already exists on NSX Manager $($nsxtManagerDetails.fqdn)"
            }
        }
        else {
            Write-Error "NSX Tier0 Gateway $tier0Gateway does not exist on NSX Manager $($nsxtManagerDetails.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-RouteMap

Function Set-DatastoreTag {
    <#
        .SYNOPSIS
        Creates and applies a vSphere Tag to a datastore

        .DESCRIPTION
        The Set-DatastoreTag cmdlet creates and applies a vSphere Tag to a datastore

        .EXAMPLE
        Set-DatastoreTag -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-w01 -tagName vsphere-with-tanzu-tag -tagCategoryName vsphere-with-tanzu-category -datastore sfo-w01-cl01-ds-vsan01
        This example creates a new tag and assigns it to the datastore in workload domain sfo-w01
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$tagName,
        [Parameter (Mandatory = $true)] [String]$tagCategoryName
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -Password $vcenter.ssoAdminPass | Out-Null
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            $datastore = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }).clusters.id) }).primaryDatastoreName
            if ($datastoreExist = Get-Datastore -Name $datastore -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq $datastore}) {
                if (!($tagAssignmentExists = Get-TagAssignment -Entity $datastoreExist.Name -Category $tagCategoryName -ErrorAction SilentlyContinue)) {
                    if (!($tagCategoryExist = Get-TagCategory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $tagCategoryName })) {
                        New-TagCategory -Name $tagCategoryName -EntityType Datastore -Confirm:$false | Out-Null
                    }
                    if (!($tagExists = Get-Tag -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $tagName })) {
                        New-Tag -Name $tagName -Category $tagCategoryName -Confirm:$false | Out-Null
                    }
                    Get-Datastore -Name $Datastore | New-TagAssignment -Tag $tagName -Confirm:$false | Out-Null
                    if (($tagAssignmentExists = Get-TagAssignment -Entity $datastoreExist.Name -Category $tagCategoryName -ErrorAction SilentlyContinue)) {
                        Write-Output  "Created vSphere Tag $tagName and applied to datastore $datastore in vCenter Server $($vcenter.fqdn) Successfully"
                    }
                    else {
                        Write-Error  "Assigning vSphere Tag $tagName to datastore $datastore in vCenter Server $($vcenter.fqdn) Failed"
                    }
                }
                else {
                    Write-Warning  "vSphere Tag $tagName has already been applied to datastore $datastore in vCenter Server $($vcenter.fqdn)"
                }
            }
            else {
                Write-Error "Datastore $datastore not found in vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
    Finally {
        #Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue
    }
}
Export-ModuleMember -Function Set-DatastoreTag

Function Add-StoragePolicy {
    <#
        .SYNOPSIS
        Create a VM vSphere Storage Policy

        .DESCRIPTION
        The Add-StoragePolicy cmdlet creates a VM vSphere Storage Policy

        .EXAMPLE
        Add-StoragePolicy -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-w01 -policyName vsphere-with-tanzu-storage-policy -tagName vsphere-with-tanzu-tag
        This example creates a VM Storage Policy named vsphere-with-tanzu-policy in the VI workload domain vCenter Server
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$policyName,
        [Parameter (Mandatory = $true)] [String]$tagName
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -Password $vcenter.ssoAdminPass -Force | Out-Null
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            if (!($getSpbmPolicy = Get-SpbmStoragePolicy -Name $policyName -ErrorAction SilentlyContinue)) {
                if ($tagExists = Get-Tag -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $tagName }) {
                    New-SpbmStoragePolicy -Name $policyName -AnyOfRuleSets (New-SpbmRuleSet -AllOfRules (New-SpbmRule -AnyOfTags $tagName)) | Out-Null
                    if ($getSpbmPolicy = Get-SpbmStoragePolicy -Name $policyName -ErrorAction SilentlyContinue) {
                        Write-Output  "Created vSphere Storage Policy $policyName in vCenter Server $($vcenter.fqdn) Successfully"
                    }
                    else {
                        Write-Error  "Creating vSphere Storage Policy $policyName in vCenter Server $($vcenter.fqdn) Failed"
                    }
                }
                else {
                    Write-Warning "vSphere $tagName does not exist in vCenter Server $($vcenter.fqdn), please create and try again"
                }
            }
            else {
                Write-Warning "Storage Policy $policyName already exists in vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
    Finally {
        #Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue
    }
}
Export-ModuleMember -Function Add-StoragePolicy

Function Add-ContentLibrary {
    <#
        .SYNOPSIS
        Creates a subscribed content library

        .DESCRIPTION
        The Add-ContentLibrary cmdlet creates a subscribed content library

        .EXAMPLE
        Add-ContentLibrary -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-w01 -contentLibraryName sfo-w01-lib01 published
        This example creates published content library named sfo-w01-lib01 in workload domain sfo-w01

        .EXAMPLE
        Add-ContentLibrary -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-w01 -contentLibraryName Kubernetes -subscriptionUrl "https://wp-content.vmware.com/v2/latest/lib.json"
        This example creates subscribed content library named Kubernetes in workload domain sfo-w01
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$contentLibraryName,
        [Parameter (ParameterSetName = 'Subscription', Mandatory = $false)] [String]$subscriptionUrl,
        [Parameter (ParameterSetName = 'Local', Mandatory = $false)] [Switch]$published
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -Password $vcenter.ssoAdminPass -Force | Out-Null
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            if (!($getContentLibrary = Get-ContentLibrary -Name $contentLibraryName -ErrorAction SilentlyContinue)) {
                $datastore = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }).clusters.id) }).primaryDatastoreName
                if ($datastoreExist = Get-Datastore -Name $datastore -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq $datastore}) {

                    if ($subscriptionUrl) {
                        #attribution to William Lam (https://gist.github.com/lamw/988e4599c0f88d9fc25c9f2af8b72c92) for this snippet
                        Invoke-RestMethod -Uri $subscriptionUrl -Method Get | Out-Null

                        $endpointRequest = [System.Net.Webrequest]::Create("$subscriptionUrl")
                        $sslThumbprint = $endpointRequest.ServicePoint.Certificate.GetCertHashString()
                        $sslThumbprint = $sslThumbprint -replace '(..(?!$))', '$1:'

                        $contentLibraryInput = @{
                            Name            = $contentLibraryName
                            Datastore       = $datastore
                            AutomaticSync   = $true
                            SubscriptionUrl = $subscriptionUrl
                            SslThumbprint   = $sslThumbprint
                        }

                        New-ContentLibrary @contentLibraryInput | Out-Null
                    }
                    elseif ($published) {
                        New-ContentLibrary -Name $contentLibraryName -Published -Datastore $datastore -Server $vcenter.fqdn | Out-Null
                    }

                    if ($getContentLibrary = Get-ContentLibrary -Name $contentLibraryName -ErrorAction SilentlyContinue) {
                        Write-Output  "Created Content Library $contentLibraryName in vCenter Server $($vcenter.fqdn) Successfully"
                    }
                    else {
                        Write-Error  "Creating Content Library $contentLibraryName in vCenter Server $($vcenter.fqdn) Failed"
                    }
                }
                else {
                    Write-Error "Datastore $datastore not found in vCenter Server $($vcenter.fqdn)"
                }
            }
            else {
                Write-Warning "Content Library $contentLibraryName already exists in vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
    Finally {
        #Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue
    }
}
Export-ModuleMember -Function Add-ContentLibrary

Function Enable-SupervisorCluster {
    <#
        .SYNOPSIS
        Enables Workload Management on a VCF cluster

        .DESCRIPTION
        The Enable-SupervisorCluster cmdlet enables Workload Management on a VCF cluster

        .EXAMPLE
        $wmClusterInput = @{
            Server = sfo-vcf01.sfo.rainpole.io
            User = administrator@vsphere.local
            Pass = 'VMw@re1!'
            Domain = sfo-m01
            SizeHint = Tiny
            ManagementVirtualNetwork = Get-VirtualNetwork -Name sfo-w01-kub-seg01
            ManagementNetworkMode = StaticRange
            ManagementNetworkStartIpAddress = 192.168.20.10
            ManagementNetworkAddressRangeSize = 5
            ManagementNetworkGateway = 192.168.20.1
            ManagementNetworkSubnetMask = 255.255.255.0
            MasterNtpServer = @(172.16.11.253, 172.16.12.253)
            Cluster = sfo-w01-cl01
            ContentLibrary = Kubernetes
            EphemeralStoragePolicy = Get-SpbmStoragePolicy -Name vsphere-with-tanzu-policy
            ImageStoragePolicy = Get-SpbmStoragePolicy -Name vsphere-with-tanzu-policy
            MasterStoragePolicy = Get-SpbmStoragePolicy -Name vsphere-with-tanzu-policy
            NsxEdgeClusterId = (Get-NsxtEdgeCluster -Name sfo-w01-ec01).Id
            DistributedSwitch = sfo-w01-cl01-vds01
            PodCIDRs = 100.100.0.0/20
            ServiceCIDR = 100.200.0.0/22
            ExternalIngressCIDRs = 192.168.21.0/24
            ExternalEgressCIDRs = 192.168.22.0/24
            WorkerDnsServer = @(172.16.11.4, 172.16.11.5)
            MasterDnsServerIpAddress = @(172.16.11.4, 172.16.11.5)
            MasterDnsSearchDomain = sfo.rainpole.io
        }

        Enable-SupervisorCluster @wmClusterInput
        This example enables Workload Management on a vSphere Cluster in workload domain sfo-w01
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$cluster,
        [Parameter (Mandatory = $true)] [String]$sizeHint,
        [Parameter (Mandatory = $true)] [String]$managementNetworkMode,
        [Parameter (Mandatory = $true)] [String]$managementVirtualNetwork,
        [Parameter (Mandatory = $true)] [String]$managementNetworkStartIpAddress,
        [Parameter (Mandatory = $true)] [String]$managementNetworkAddressRangeSize,
        [Parameter (Mandatory = $true)] [String]$managementNetworkGateway,
        [Parameter (Mandatory = $true)] [String]$managementNetworkSubnetMask,
        [Parameter (Mandatory = $true)] [String]$ntpServer1IpAddress,
        [Parameter (Mandatory = $false)] [String]$ntpServer2IpAddress,
        [Parameter (Mandatory = $true)] [String]$dnsServer1IpAddress,
        [Parameter (Mandatory = $false)] [String]$dnsServer2IpAddress,
        [Parameter (Mandatory = $true)] [String]$contentLibrary,
        [Parameter (Mandatory = $true)] [String]$ephemeralStoragePolicy,
        [Parameter (Mandatory = $true)] [String]$imageStoragePolicy,
        [Parameter (Mandatory = $true)] [String]$masterStoragePolicy,
        [Parameter (Mandatory = $true)] [String]$nsxEdgeCluster,
        [Parameter (Mandatory = $true)] [String]$distributedSwitch,
        [Parameter (Mandatory = $true)] [String]$podCIDRs,
        [Parameter (Mandatory = $true)] [String]$serviceCIDR,
        [Parameter (Mandatory = $true)] [String]$externalIngressCIDRs,
        [Parameter (Mandatory = $true)] [String]$externalEgressCIDRs,
        [Parameter (Mandatory = $true)] [String]$masterDnsSearchDomain,
        [Parameter (Mandatory = $true)] [ValidateSet("true", "false")] [String]$async
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -Password $vcenter.ssoAdminPass -Force | Out-Null
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            $nsxtManagerDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain
            Request-NsxToken -fqdn $nsxtManagerDetails.fqdn -username $nsxtManagerDetails.adminUser -password $nsxtManagerDetails.adminPass | Out-Null
            if (!($getWMCluster = Get-WMCluster -Cluster $cluster -ErrorAction SilentlyContinue)) {

                if ($NtpServer2IpAddress) {
                    $ntpServers = @($NtpServer1IpAddress, $NtpServer2IpAddress)
                }
                else {
                    $ntpServers = @($NtpServer1IpAddress)
                }

                if ($DnsServer2IpAddress) {
                    $dnsServers = @($DnsServer1IpAddress, $DnsServer2IpAddress)
                }
                else {
                    $dnsServers = @($DnsServer1IpAddress)
                }

                $internalWMClusterInput = @{
                    SizeHint                          = $SizeHint
                    ManagementVirtualNetwork          = Get-VirtualNetwork -Name $ManagementVirtualNetwork
                    ManagementNetworkMode             = $managementNetworkMode
                    ManagementNetworkStartIpAddress   = $managementNetworkStartIpAddress
                    ManagementNetworkAddressRangeSize = $managementNetworkAddressRangeSize
                    ManagementNetworkGateway          = $managementNetworkGateway
                    ManagementNetworkSubnetMask       = $managementNetworkSubnetMask
                    MasterNtpServer                   = $ntpServers
                    Cluster                           = $cluster
                    ContentLibrary                    = $contentLibrary
                    EphemeralStoragePolicy            = Get-SpbmStoragePolicy -Name $ephemeralStoragePolicy
                    ImageStoragePolicy                = Get-SpbmStoragePolicy -Name $imageStoragePolicy
                    MasterStoragePolicy               = Get-SpbmStoragePolicy -Name $masterStoragePolicy
                    NsxEdgeClusterId                  = (Get-NsxtEdgeCluster -Name $nsxEdgeCluster).Id
                    DistributedSwitch                 = $distributedSwitch
                    PodCIDRs                          = $podCIDRs
                    ServiceCIDR                       = $serviceCIDR
                    ExternalIngressCIDRs              = $externalIngressCIDRs
                    ExternalEgressCIDRs               = $externalEgressCIDRs
                    WorkerDnsServer                   = $dnsServers
                    MasterDnsServerIpAddress          = $dnsServers
                    MasterDnsSearchDomain             = $dnsSearchDomain
                }

                if ($async -eq "true") {
                    Enable-WMCluster @internalWMClusterInput -RunAsync | Out-Null
                    Write-Output  "Submitted Creation of Supervisor Cluster $cluster in vCenter Server $($vcenter.fqdn), this takes a while"
                }
                if ($async -eq "false") {
                    Enable-WMCluster @internalWMClusterInput | Out-Null
                    if ($getWMCluster = Get-WMCluster -Cluster $cluster -ErrorAction SilentlyContinue) {
                        Write-Output  "Created Supervisor Cluster $cluster in vCenter Server $($vcenter.fqdn) Successfully"
                    }
                    else {
                        Write-Error  "Creating Supervisor Cluster $cluster in vCenter Server $($vcenter.fqdn) Failed"
                    }
                }
            }
            else {
                Write-Warning "Supervisor Cluster $cluster has already been enabled in vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Enable-SupervisorCluster

Function Add-Namespace {
    <#
        .SYNOPSIS
        Creates a Namespace and applies extra configuration to it

        .DESCRIPTION
        The Add-Namespace cmdlet creates a Namespace and applies extra configuration to it

        .EXAMPLE
        Add-Namespace -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-w01 -cluster sfo-w01-cl01 -namespace sfo-w01-ns01 -storagePolicy vsphere-with-tanzu-storage-policy
        This example creates a Namespace named sfo-w01-ns01 in the Supervisor Cluster sfo-w01-cl01 with a vSphere Storage Policy vsphere-with-tanzu-storage-policy
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$cluster,
        [Parameter (Mandatory = $true)] [String]$namespace,
        [Parameter (Mandatory = $true)] [String]$storagePolicy
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -Password $vcenter.ssoAdminPass -Force | Out-Null
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            if (!($getNamespace = Get-WMNamespace -Name $namespace -ErrorAction SilentlyContinue)) {
                if ($clusterExists = Get-Cluster -Name $cluster -ErrorAction SilentlyContinue) {
                    if ($storagePolicyExists = Get-SpbmStoragePolicy -Name $storagePolicy -ErrorAction SilentlyContinue) {
                        New-WMNamespace -Name $namespace -Cluster $cluster | Out-Null
                        if ($getNamespace = Get-WMNamespace -Name $namespace -ErrorAction SilentlyContinue) {
                            New-WMNamespaceStoragePolicy -Namespace $namespace -StoragePolicy $storagePolicy | Out-Null
                            Write-Output  "Created Namespace $namespace in vCenter Server $($vcenter.fqdn) Successfully"
                        }
                        else {
                            Write-Error "Creation of Namespace $namespace in vCenter Server $($vcenter.fqdn) Failed"
                        }
                    }
                    else {
                        Write-Error "vSphere Storage Policy $storagePolicy not found in vCenter Server $($vcenter.fqdn)"
                    }
                }
                else {
                    Write-Error  "Cluster $cluster not found in vCenter Server $($vcenter.fqdn)"
                }
            }
            else {
                Write-Warning "Namespace $namespace already exists in vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
    Finally {
        #Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue
    }
}
Export-ModuleMember -Function Add-Namespace

Function Add-NamespacePermission {
    <#
        .SYNOPSIS
        Adds permissions to a Namespace

        .DESCRIPTION
        The Add-NamespacePermission cmdlet adds permissions to a Namespace

        .EXAMPLE
        Add-NamespacePermission -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -domain sfo.rainpole.io -domainBindUser svc-vsphere-ad -domainBindPass VMw@re1! -namespace sfo-w01-ns01 -principal gg-kub-admins -role edit -type group
        This example adds the edit role to the group gg-kub-admins in the domain sfo.rainpole.io to the Namespace sfo-w01-ns01
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainBindUser,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainBindPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$namespace,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$principal,
        [Parameter (Mandatory = $true)] [ValidateSet("edit", "view")] [String]$role,
        [Parameter (Mandatory = $true)] [ValidateSet("group", "user")] [String]$type,
        [Parameter (Mandatory = $true)] [ValidateSet("true", "false")] [String]$disconnect
    )

    Try {
        $checkAdAuthentication = Test-ADAuthentication -user $domainBindUser -pass $domainBindPass -server $domain -domain $domain -ErrorAction SilentlyContinue
        if ($checkAdAuthentication[1] -match "Authentication Successful") {
            $securePass = ConvertTo-SecureString -String $domainBindPass -AsPlainText -Force
            $domainCreds = New-Object System.Management.Automation.PSCredential ($domainBindUser, $securePass)
            $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $sddcDomain
            Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -Password $vcenter.ssoAdminPass -Force | Out-Null
            if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
                if ($namespaceExists = Get-WMNamespace -Name $namespace -ErrorAction SilentlyContinue) {
                    if ($type -eq "group") { $adObjectCheck = (Get-ADGroup -Server $domain -Credential $domainCreds -Filter { SamAccountName -eq $principal }) }
                    elseif ($type -eq "user") { $adObjectCheck = (Get-ADUser -Server $domain -Credential $domainCreds -Filter { SamAccountName -eq $principal }) }
                    if ($adObjectCheck) {
                        if (!($permissionExist = Get-WMNamespacePermission -Namespace $namespace -Domain $domain -PrincipalName $principal)) {
                            New-WMNamespacePermission -Namespace $namespace -Role $role -Domain $domain -PrincipalType $type -PrincipalName $principal | Out-Null
                            if ($permissionExist = Get-WMNamespacePermission -Namespace $namespace -Domain $domain -PrincipalName $principal) {
                                Write-Output "Assigned Role $role to $type $principal in Namespace $namespace Successfully"
                            }
                            else {
                                Write-Error "Assigning Role $role to $type $principal in Namespace $namespace Failed"
                            }
                        }
                        else {
                            Write-Warning "Principal $type $principal already assigned permission $role to Namespace $namespace"
                        }
                    }
                    else {
                        Write-Error "Active Directory $type $principal not found in the Active Directory Domain, please create and retry"
                    }
                }
                else {
                    Write-Error "Namespace $namespace does not exist in vCenter Server $($vcenter.fqdn)"
                }
            }
            else {
                Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error  "Unable to authenticate to Active Directory with user $domainBindUser and password $domainBindPass, verify they are correct and try again"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
    Finally {
        if ($disconnect -eq "true") {
            #Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue
        }
    }
}
Export-ModuleMember -Function Add-NamespacePermission

Function Enable-Registry {
    <#
        .SYNOPSIS
        Enable the embedded Harbor Registry on a Supervisor Cluster

        .DESCRIPTION
        The Enable-Registry cmdlet enables the embedded Harbor Registry on a Supervisor Cluster

        .EXAMPLE
        Enable-Registry -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-w01 -storagePolicy vsphere-with-tanzu-storage-policy
        This example enables the embedded Harbor Registry on Supervisor Cluster sfo-w01-cl01 with vSPhere Storage Policy vsphere-with-tanzu-policy

    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$storagePolicy
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -Password $vcenter.ssoAdminPass -Force | Out-Null
        Request-vSphereApiToken -Fqdn $vcenter.fqdn -Username $vcenter.ssoadmin -Password $vcenter.ssoAdminPass | Out-Null
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            $cluster = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $domain }).clusters.id) }).Name
            if (!($getRegistry = Get-WMRegistry -Cluster $cluster -ErrorAction SilentlyContinue)) {
                if ($getStoragePolicy = Get-SpbmStoragePolicy -Name $StoragePolicy -ErrorAction SilentlyContinue) {
                    Enable-WMRegistry -Cluster $cluster -StoragePolicy $storagePolicy | Out-Null
                    if ($getRegistry = Get-WMRegistry -Cluster $cluster -ErrorAction SilentlyContinue) {
                        Write-Output "Enabled the Embedded Registry Service on cluster $cluster in vCenter Server $($vcenter.fqdn) Successfully"
                    }
                    else {
                        Write-Error "Enabling the Embedded Registry Service on cluster $cluster in vCenter Server $($vcenter.fqdn) Failed"
                    }
                }
                else {
                    Write-Error -Message "vSphere Storage Policy $storagePolicy does not exist in vCenter Server $($vcenter.fqdn)"
                }
            }
            else {
                Write-Warning "The Embedded Registry Service has already been enabled on cluster $cluster in vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
    Finally {
        #Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue
    }
}
Export-ModuleMember -Function Enable-Registry

Function Connect-SupervisorCluster {
    <#
        .SYNOPSIS
        Log in to a Supervisor Cluster

        .DESCRIPTION
        The Connect-SupervisorCluster cmdlet logs the user in to a Supervisor Cluster

        .EXAMPLE
        Connect-WMCluster -Cluster sfo-w01-cl01 -User administrator@vsphere.local -Pass VMw@re1!
        This example logs the vSphere SSO user administrator@vsphere.local into Supervisor Cluster sfo-w01-cl01
    #>

    Param (
        [Parameter (Mandatory = $true)][string]$Server,
        [Parameter (Mandatory = $true)][string]$User,
        [Parameter (Mandatory = $true)][string]$Pass,
        [Parameter (Mandatory = $true)][string]$Domain,
        [Parameter (Mandatory = $true)][string]$Cluster
    )

    if ($accessToken) {
        checkVCFToken
    }
    else {
        Request-VCFToken -fqdn $Server -username $User -password $Pass | Out-Null
    }

    Try {
        $viserver = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
        Connect-VIServer -Server $viserver.fqdn -User $viserver.ssoAdmin -Password $viserver.ssoAdminPass -Force | Out-Null
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }

    Try {
        $kubIpAddress = (Get-WMCluster -Cluster $Cluster).KubernetesHostname
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }

    Try {
        Start-AwaitSession | Out-Null
        Send-AwaitCommand "kubectl vsphere login --server $kubIpAddress --vsphere-username $User --insecure-skip-tls-verify" | Out-Null
        Wait-AwaitResponse "Password:" | Out-Null
        Send-AwaitCommand "$Pass"
        Stop-AwaitSession
        Start-Sleep -seconds 3 | Out-Null
    }
    Catch {
        Write-Error "Something went wrong."
    }

    $tryKubectl = Invoke-Expression "kubectl get nodes"

    if ($tryKubectl) {
        Write-Output "Connection successful."
    }
}
Export-ModuleMember -Function Connect-Supervisor

Function Add-TanzuKubernetesCluster {
    <#
        .SYNOPSIS
        Create a new Tanzu Kubernetes Cluster on a VCF-deployed Supervisor Cluster

        .DESCRIPTION
        The Add-TanzuKubernetesCluster cmdlet creates a new Tanzu Kubernetes Cluster on a VCF-deployed Supervisor Cluster

        .EXAMPLE
        Add-TanzuKubernetesCluster -Server sfo-vcf01.sfo.rainpole.io -User administrator@vsphere.local -Pass VMware123! -Domain sfo-w01 -Cluster sfo-w01-cl01 -YAML c:\kube\sfo-w01-tkc01.yaml
        This example creates a Tanzu Kubernetes cluster based on YAML in c:\kube\sfo-w01-tkc01.yaml as the vSphere SSO user administrator@vsphere.local on Supervisor Cluster sfo-w01-cl01
    #>

    Param (
        [Parameter (Mandatory = $true)][string]$Server,
        [Parameter (Mandatory = $true)][string]$User,
        [Parameter (Mandatory = $true)][string]$Pass,
        [Parameter (Mandatory = $true)][string]$Domain,
        [Parameter (Mandatory = $true)][string]$Cluster,
        [Parameter (Mandatory = $true)][string]$YAML
    )

    if ($accessToken) {
        checkVCFToken
    }
    else {
        Request-VCFToken -fqdn $Server -username $User -password $Pass | Out-Null
    }

    Try {
        $viserver = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
        Connect-VIServer -Server $viserver.fqdn -User $viserver.ssoAdmin -Password $viserver.ssoAdminPass -Force | Out-Null
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }

    Try {
        $kubIpAddress = (Get-WMCluster -Cluster $Cluster).KubernetesHostname
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }

    Try {
        Connect-SupervisorCluster -Server $Server -User $User -Pass $Pass -Domain $Domain -Cluster $Cluster | Out-Null
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }

    Try {
        New-TanzuKubernetesCluster -YAML $YAML
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-TanzuKubernetesCluster

##########################################  E N D   O F   F U N C T I O N S  ##########################################
#######################################################################################################################


#######################################################################################################################
#################   S H A R E D   P O W E R   V A L I D A T E D  S O L U T I O N   F U N C T I O N S   ################

Function Add-vCenterGlobalPermission {
    <#
		.SYNOPSIS
    	Adds a Global Permission to user/group

    	.DESCRIPTION
    	The Add-vCenterGlobalPermission cmdlets assigns the vCenter Server Global Permission to the user or group provided.
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values to retrive the management domain
        vCenter Server details from its inventory and then:
        - Verifies that the bind credentials are valid
        - Verifies that the domain is present in vCenter Server as an Identity Provider
        - Verifies the user or group exists in Active Directory
        - Assigns the user or group to the Global Permission

		If -localDomain is selected, then AD authentication check is skipped and user/group is checked for in the local directory

    	.EXAMPLE
    	Add-vCenterGlobalPermission -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo.rainpole.io -domainBindUser svc-vsphere-ad -domainBindPass VMw@re1! -principal gg-vc-admins -role Admin -propagate true -type group
        This example adds the group gg-vc-admins from domain sfo.rainpole.io the Administrator Global Permission

        .EXAMPLE
		Add-vCenterGlobalPermission -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain vsphere.local -domainBindUser administrator -domainBindPass VMw@re1! -principal svc-sfo-m01-nsx01-sfo-m01-vc01 -role "NSX-T Data Center to vSphere Integration" -propagate true -type user -localdomain
		This example adds the "NSX-T Data Center to vSphere Integration" Global Permission to the user svc-sfo-m01-nsx01-sfo-m01-vc01 from domain vsphere.local
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainBindUser,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainBindPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$principal,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$role,
        [Parameter (Mandatory = $true)] [ValidateSet("true", "false")] [String]$propagate,
        [Parameter (Mandatory = $true)] [ValidateSet("group", "user")] [String]$type,
		[Parameter (Mandatory = $false)] [Switch]$localDomain = $false
    )

    Try {
		if (!$localDomain){
			$checkAdAuthentication = Test-ADAuthentication -user $domainBindUser -pass $domainBindPass -server $domain -domain $domain -ErrorAction SilentlyContinue
			if (!($checkAdAuthentication[1] -match "Authentication Successful")) {
				Write-Error  "Unable to authenticate to Active Directory with user '$domainBindUser' and password '$domainBindPass', verify they are correct and try again"
				Return
			}
		}

		$securePass = ConvertTo-SecureString -String $domainBindPass -AsPlainText -Force
		$domainCreds = New-Object System.Management.Automation.PSCredential ($domainBindUser, $securePass)
		$vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domainType MANAGEMENT
		Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -Pass $vcenter.ssoAdminPass | Out-Null
		if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
			Connect-SsoAdminServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -Password $vcenter.ssoAdminPass | Out-Null
            if ($DefaultSsoAdminServers.Name -eq $($vcenter.fqdn)) {
                if (!(Get-IdentitySource | Where-Object { $_.Name -eq $domain })) {
                    Write-Error "Identity Source $domain not found in vCenter Server $($vcenter.fqdn)"
                }
                else {
                    if ($type -eq "group") {
                        if (!$localDomain) {
                            $objectCheck = (Get-ADGroup -Server $domain -Credential $domainCreds -Filter { SamAccountName -eq $principal })
                        }
                        else {
                            $principal = $domain.ToUpper() + "\" + $principal
                            $objectCheck = (Get-VIAccount -Group -Domain vsphere.local | Where-Object { $_.Name -eq $principal })
                        }
                    }
                    elseif ($type -eq "user") {
                        if (!$localDomain){
                            $objectCheck = (Get-ADUser -Server $domain -Credential $domainCreds -Filter { SamAccountName -eq $principal })
                            $principal = $domain.ToUpper() + "\" + $principal
                        }
                        else {
                            $principal = $domain.ToUpper() + "\" + $principal
                            $objectCheck = (Get-VIAccount -User -Domain vsphere.local | Where-Object { $_.Name -eq $principal })
                        }
                    }
                    if ($objectCheck) {
                        $roleId = (Get-VIRole -Name $role | Select-Object -ExpandProperty Id)
                        Add-GlobalPermission -vcServer $vcenter.fqdn -vcUsername $vcenter.ssoAdmin -vcPassword $vcenter.ssoAdminPass -roleId $roleId -user $principal -propagate $propagate -type $type
                        Write-Output "Assigned Global Permission Role $role to $type '$principal' in vCenter Server $($vcenter.fqdn) Successfully"
                    }
                    else {
                        if ($localDomain) {
                            Write-Error "$type '$principal' not found in the Local Domain, please create and retry"
                        }
                        else {
                            Write-Error "Active Directory $type '$principal' not found in the Active Directory Domain, please create and retry"
                        }
                    }
                }
            }
            else {
                Write-Error  "Not connected to vCenter Single-Sign On $($vcenter.fqdn)"
            }
		}
        else {
			Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
		}
		Disconnect-SsoAdminServer $vcenter.fqdn -WarningAction SilentlyContinue
		Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-vCenterGlobalPermission

Function Set-vCenterPermission {
	<#
		.SYNOPSIS
    	Sets Permission for user or group in the vCenter server. This overrides any existing Global permissions for the user or group in the vCenter server

    	.DESCRIPTION
    	The Set-vCenterPermission cmdlet assigns the Permission/Role to existing user or group in the vCenter server.
		The user/group must exist in the domain prior to running this cmdlet

    	.EXAMPLE
    	Set-vCenterPermission -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain vsphere.local -workloadDomain sfo-m01 -principal svc-sfo-w01-nsx01-sfo-w01-vc01 -role "NoAccess"
		This example assigns NoAccess permission to the user svc-sfo-w01-nsx01-sfo-w01-vc01 from domain vsphere.local

        .EXAMPLE
		Set-vCenterPermission -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo -workloadDomain sfo-m01 -principal gg-vc-admins -role "Admin"
        This example assigns Admin permission to the group gg-vc-admins from domain sfo
  	#>

	Param (
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$workloadDomain,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$principal,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$role
	)

	Try {
		$vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $workloadDomain
		Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
		if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
			$principal = $domain.ToUpper() + "\" + $principal
			$objectCheck = Get-VIPermission -Server $vcenter.fqdn | Where-Object { $_.Principal -eq $principal }
            if ($objectCheck) {
                if (!($objectCheck.Role -eq $role)) {
                    New-VIPermission -Server $vcenter.fqdn -Role $role -Principal $principal -Entity (Get-Folder "Datacenters" -Type Datacenter | Where-Object {$_.Uid -like "*"+$vcenter.fqdn+"*"}) | Out-Null
                    $objectCheck = Get-VIPermission -Server $vcenter.fqdn | Where-Object { $_.Principal -eq $principal }
                    if ($objectCheck.Role -eq $role) {
                        Write-Output "Assigned $role permission to $principal Successfully"
                    }
                    else {
                        Write-Error "Assigning $role permission to $principal failed, please retry"
                    }
                }
                else {
                    Write-Warning "Role $($objectCheck.Role) assigned to $principal already"
                }
            }
            else {
				Write-Error "$principal not found in the vCenter Server $($vcenter.fqdn)"
			}
            Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
		}
        else {
			Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
		}
	}
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Set-vCenterPermission

Function Add-SsoPermission {
    <#
		.SYNOPSIS
    	Assign vCenter Single Sign-On Group to user/group

    	.DESCRIPTION
    	The Add-SsoPermission cmdlet assigns the vCenter Single Sign-On Role to the user or group provided.
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values to retrive the management domain
        vCenter Server details from its inventory and then:
        - Verifies that the bind credetials are valid
        - Verifies that the domain is present in vCenter Server as an Identity Provider
        - Verifies the user or group exists in Active Directory
        - Assigns the user or group to the vCenter Single Sign-On Role

    	.EXAMPLE
    	Add-SsoPermission -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-m01 -domain sfo.rainpole.io -domainBindUser svc-vsphere-ad -domainBindPass VMw@re1! -principal gg-sso-admins -ssoGroup "Administrators" -type group -source external
        This example adds the group gg-sso-admins from domain sfo.rainpole.io to the Administrators vCenter Single Sign-On Group

        .EXAMPLE
    	Add-SsoPermission -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-m01 -domain vsphere.local -principal svc-sfo-m01-nsx01-sfo-m01-vc01 -ssoGroup "License.Administrators" -type user -source local
        This example adds the user svc-sfo-m01-nsx01-sfo-m01-vc01 from domain vspherel.local to the License.Administrators vCenter Single Sign-On Group
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$domainBindUser,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$domainBindPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$principal,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ssoGroup,
        [Parameter (Mandatory = $true)] [ValidateSet("group", "user")] [String]$type,
        [Parameter (Mandatory = $true)] [ValidateSet("local", "external")] [String]$source
    )

    Try {
        if ($source -eq "external") {
            $checkAdAuthentication = Test-ADAuthentication -user $domainBindUser -pass $domainBindPass -server $domain -domain $domain -ErrorAction SilentlyContinue
            if ($checkAdAuthentication[1] -match "Authentication Successful") {
                $securePass = ConvertTo-SecureString -String $domainBindPass -AsPlainText -Force
                $domainCreds = New-Object System.Management.Automation.PSCredential ($domainBindUser, $securePass)
                $ssoServer = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $sddcDomain
                $ssoConnection = Connect-SsoAdminServer -Server $ssoServer.fqdn -User $ssoServer.ssoAdmin -Password $ssoServer.ssoAdminPass
                if ($DefaultSsoAdminServers.Name -eq $($ssoServer.fqdn)) {
                    $targetGroup = Get-SsoGroup -Domain vsphere.local -Name $ssoGroup -Server $ssoConnection
                    if (Get-IdentitySource -Server $ssoConnection | Where-Object { $_.Name -eq $domain }) {
                        if ($type -eq "group") {
                            $adObjectCheck = (Get-ADGroup -Server $domain -Credential $domainCreds -Filter { SamAccountName -eq $principal })
                            if ($adObjectCheck) {
                                if (!(Get-SsoGroup -Group $targetGroup -Name $principal)) {
                                    $ldapGroup = Get-SsoGroup -Domain $domain -Name $principal -Server $ssoConnection
                                    $ldapGroup | Add-GroupToSsoGroup -TargetGroup $targetGroup -ErrorAction SilentlyContinue
                                    if (Get-SsoGroup -Group $targetGroup -Name $principal) {
                                        Write-Output "Assigned Active Directory $type '$principal' from Identity Provider '$domain' to vCenter Single-Sign On Group '$ssoGroup' Successfully"
                                    }
                                    else {  Write-Error "Adding Active Directory $type '$principal' from Identity Provider '$domain' to vCenter Single-Sign On Group '$ssoGroup' Failed"
                                    }
                                }
                                else { Write-Warning "Active Directory $type '$principal' from Identity Provider '$domain' already added to vCenter Single-Sign On Group $ssoGroup"
                                }
                            }
                            else { Write-Error "Active Directory $type '$principal' not found in the Active Directory Domain '$domain', please create and retry"
                            }
                        }
                        elseif ($type -eq "user") {
                            $adObjectCheck = (Get-ADUser -Server $domain -Credential $domainCreds -Filter { SamAccountName -eq $principal })
                            if ($adObjectCheck) {
                                if (!(Get-SsoPersonUser -Group $targetGroup | Where-Object {$_.Name -eq $principal})) {
                                    $ldapUser = Get-SsoPersonUser -Domain $domain -Name $principal -Server $ssoConnection
                                    $ldapUser | Add-UserToSsoGroup -TargetGroup $targetGroup -ErrorAction SilentlyContinue
                                    if (Get-SsoPersonUser -Group $targetGroup | Where-Object {$_.Name -eq $principal}) {
                                        Write-Output "Assigned Active Directory $type '$principal' from Identity Provider '$domain' to vCenter Single-Sign On Group '$ssoGroup' Successfully"
                                    }
                                    else { Write-Error "Adding Active Directory $type '$principal' from Identity Provider '$domain' to vCenter Single-Sign On Group '$ssoGroup' Failed"
                                    }
                                }
                                else { Write-Warning "Active Directory $type '$principal' from Identity Provider '$domain' to already added to vCenter Single-Sign On Group $ssoGroup"
                                }
                            }
                            else { Write-Error "Active Directory $type '$principal' not found in the Active Directory Domain '$domain', please create and retry"
                            }
                        }
                    }
                    else {
                        Write-Error "Identity Provider '$domain' not found in vCenter Single-Sign On, please create and retry"
                    }
                    Disconnect-SsoAdminServer -Server $ssoServer.fqdn
                }
                else {
                    Write-Error  "Not connected to vCenter Single-Sign On $($ssoServer.fqdn)"
                }
            }
            else {
                Write-Error  "Unable to authenticate to Active Directory with user '$domainBindUser' and password '$domainBindPass', verify they are correct and try again"
            }
        }
        elseif ($source -eq "local") {
            $ssoServer = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $sddcDomain
            $ssoConnection = Connect-SsoAdminServer -Server $ssoServer.fqdn -User $ssoServer.ssoAdmin -Password $ssoServer.ssoAdminPass
            if ($DefaultSsoAdminServers.Name -eq $($ssoServer.fqdn)) {
                $targetGroup = Get-SsoGroup -Domain vsphere.local -Name $ssoGroup -Server $ssoConnection
                if (Get-IdentitySource | Where-Object { $_.Name -eq $domain }) {
                    if ($type -eq "group") {
                        if (!(Get-SsoGroup -Group $targetGroup -Name $principal -Server $ssoConnection)) {
                            $ldapGroup = Get-SsoGroup -Domain $domain -Name $principal -Server $ssoConnection
                            $ldapGroup | Add-GroupToSsoGroup -TargetGroup $targetGroup -ErrorAction SilentlyContinue
                            if (Get-SsoGroup -Group $targetGroup -Name $principal -Server $ssoConnection) {
                                Write-Output "Assigned $type '$principal' from Identity Provider '$domain' to vCenter Single-Sign On Group '$ssoGroup' Successfully"
                            }
                            else {  Write-Error "Adding $type '$principal' from Identity Provider '$domain' to vCenter Single-Sign On Group '$ssoGroup' Failed"
                            }
                        }
                        else { Write-Warning "$type '$principal' from Identity Provider '$domain' already added to vCenter Single-Sign On Group $ssoGroup"
                        }
                    }
                    elseif ($type -eq "user") {
                        if (!(Get-SsoPersonUser -Group $targetGroup -Server $ssoConnection | Where-Object {$_.Name -eq $principal})) {
                            $ldapUser = Get-SsoPersonUser -Domain $domain -Name $principal -Server $ssoConnection
                            $ldapUser | Add-UserToSsoGroup -TargetGroup $targetGroup -ErrorAction SilentlyContinue
                            if (Get-SsoPersonUser -Group $targetGroup -Server $ssoConnection| Where-Object {$_.Name -eq $principal}) {
                                Write-Output "Assigned $type '$principal' from Identity Provider '$domain' to vCenter Single-Sign On Group '$ssoGroup' Successfully"
                            }
                            else { Write-Error "Adding $type '$principal' from Identity Provider '$domain' to vCenter Single-Sign On Group '$ssoGroup' Failed"
                            }
                        }
                        else { Write-Warning "$type '$principal' from Identity Provider '$domain' already added to vCenter Single-Sign On Group $ssoGroup"
                        }
                    }
                }
                else {
                    Write-Error "Identity Provider '$domain' not found in vCenter Single-Sign On, please create and retry"
                }
                Disconnect-SsoAdminServer -Server $ssoServer.fqdn
            }
            else {
                Write-Error  "Not connected to vCenter Single-Sign On $($ssoServer.fqdn)"
            }
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-SsoPermission

Function Add-vSphereRole {
    <#
        .SYNOPSIS
        Add a vSphere role

        .DESCRIPTION
        The Add-vSphereRole cmdlet creates a role in vCenter Server. The cmdlet connects to SDDC Manager using the -server, -user,
        and -password values to retrive the management domain vCenter Server details from its inventory and then:
        - Verifies if the role already exists and if not creates it
        - Assigns permissions to the role based on the template file provided

        .EXAMPLE
        Add-vSphereRole -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -roleName "NSX-T Data Center to vSphere Integration" -template .\vSphereRoles\nsx-vsphere-integration.role
        This example adds the nsx-vsphere-integration role in the management domain vCenter Server
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$roleName,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$template
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("template")) {
            $template = Get-ExternalFileName -title "Select the vSphere role template (.role)" -fileType "role" -location "C:\Program Files\WindowsPowerShell\Modules\PowerValidatedSolutions\vSphereRoles"
        }
        else {
            if (!(Test-Path -Path $template)) {
                Write-Error  "vSphere Role Template '$template' File Not Found"
                Break
            }
        }

        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domainType MANAGEMENT
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            $roleContent = Get-Content -Path $template
            $checkRole = Get-VIRole -Server $vcenter.fqdn | Where-Object { $_.Name -eq $roleName }
            if (!$checkRole ) {
                New-VIRole -Name $roleName -Server $vcenter.fqdn | Out-Null
                Write-Output "Created new role '$roleName' in vCenter Server $($vcenter.fqdn) Successfully"
            }
            else {
                Write-Warning "Role '$roleName' already exists in $($vcenter.fqdn)"
            }
            Foreach ($privilege in $roleContent) {
                if (-not ($privilege -eq $null -or $privilege -eq "")) {
                    Set-VIRole -Server $vcenter.fqdn -Role $roleName -AddPrivilege (Get-VIPrivilege -ID $privilege) -Confirm:$False -ErrorAction SilentlyContinue | Out-Null
                }
            }
            Write-Output "Assigned all privileges from the template file to role '$roleName' in vCenter Server $($vcenter.fqdn) Successfully"

            Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
        }
        else {
            Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-vSphereRole

Function Add-VMFolder {
    <#
    	.SYNOPSIS
    	Create a VM Folder

    	.DESCRIPTION
    	The Add-VMFolder cmdlet creates a VM and Template folder. The cmdlet connects to SDDC Manager using the -server, -user, and -password values
        to retrive the vCenter Server details from its inventory and then:
        - Verifies that the folder has not already been created
        - Creates the folder

    	.EXAMPLE
    	Add-VMFolder -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -foldername "myFolder"
    	This example shows how to create the folder myFolder within the VMware Cloud Foundation domain sfo-m01
  	#>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$folderName
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain -ErrorAction SilentlyContinue
        if ($vcenter) {
            Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
            if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
                $cluster = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }).clusters.id) }).Name
                $datacenter = (Get-Datacenter -Cluster $cluster -Server $vcenter.fqdn).Name
                $folderExists = (Get-Folder -Name $folderName -Server $vcenter.fqdn -WarningAction SilentlyContinue -ErrorAction Ignore)
                if ($folderExists) {
                    Write-Warning "The VM and Template Folder '$folderName' already exists"
                }
                else {
                    $folder = (Get-View -Server $vcenter.fqdn (Get-View -Server $vcenter.fqdn -viewtype datacenter -filter @{"name" = [String]$datacenter }).vmfolder).CreateFolder($folderName)
                    $folderExists = (Get-Folder -Name $folderName -Server $vcenter.fqdn -WarningAction SilentlyContinue -ErrorAction Ignore)
                    if ($folderExists) {
                        Write-Output  "Created VM and Template Folder '$folderName' in vCenter Server Successfully"
                    }
                    else {
                        Write-Error "Creating VM and Template Folder '$folderName' in vCenter Server Failed"
                    }
                }
                Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
            }
            else {
                Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error "Workload domain name does not exist in SDDC Manager"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-VMFolder

Function Add-AntiAffinityRule {
    <#
    	.SYNOPSIS
    	Creates a vSphere Anti-Affinity rule

    	.DESCRIPTION
    	The Add-AntiAffinityRule cmdlet creates a vSphere Anti-Affinity rule. The cmdlet connects to SDDC Manager using the -server, -user, and -password values
        to retrive the vCenter Server details from its inventory and then:
        - Verifies that the anti-affinity rule has not already been created
        - Creates the anti-affinity rule

    	.EXAMPLE
    	Add-AntiAffinityRule -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -ruleName sfo-m01-anti-affinity-rule-wsa -antiAffinityVMs "xreg-wsa01a,xreg-wsa01b,xreg-wsa01c"
    	This example shows how to create a vSphere Anti-Affinity rule in the vCenter Server of the sfo-m01 workload domain
  	#>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$ruleName,
        [Parameter (Mandatory = $true)] [String]$antiAffinityVMs
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain -ErrorAction SilentlyContinue
        if ($vcenter) {
            Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
            if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
                $cluster = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }).clusters.id) }).Name
                $antiAffinityRuleExists = (Get-Cluster -Name $cluster | Get-DrsRule | Where-Object {$_.Name -eq $ruleName})
                if ($antiAffinityRuleExists) {
                    Write-Warning "The Anti-Affinity Rule '$ruleName' already exists"
                }
                else {
                    $vmNames = $antiAffinityVMs.split(",")
                    $vms = foreach ($name in $vmNames) { Get-VM -name $name -ErrorAction SilentlyContinue }
                    New-DrsRule -Cluster $cluster -Name $ruleName -VM $vms -KeepTogether $false -Enabled $true | Out-Null
                    $antiAffinityRuleExists = (Get-Cluster -Name $cluster | Get-DrsRule | Where-Object {$_.Name -eq $ruleName})
                    if ($antiAffinityRuleExists) {
                        Write-Output "Created vSphere Anti-Affinity Rule '$ruleName' in vCenter Server '$($vcenter.fqdn)' Successfully"
                    }
                    else {
                        Write-Error "Creating vSphere Anti-Affinity Rule '$ruleName' in vCenter Server '$($vcenter.fqdn)' Failed, Please Retry"
                    }
                }
                Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
            }
            else {
                Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error "Workload domain name does not exist in SDDC Manager"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-AntiAffinityRule

Function Add-ClusterGroup {
    <#
    	.SYNOPSIS
    	Creates a vSphere DRS Cluster Group

    	.DESCRIPTION
    	The Add-ClusterGroup cmdlet creates a vSphere DRS Cluster Group. The cmdlet connects to SDDC Manager using the -server, -user, and -password values
        to retrive the vCenter Server details from its inventory and then:
        - Verifies that that the vSphere DRS Cluster Group does not already exist
        - Creates the vSphere DRS Cluster Group

    	.EXAMPLE
    	Add-ClusterGroup -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -drsGroupName "Clustered Workspace ONE Access Appliances" -drsGroupVMs "xreg-wsa01a,xreg-wsa01b,xreg-wsa01c"
    	This example shows how to create a vSphere DRS Cluster group in the vCenter Server of the sfo-m01 workload domain
  	#>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$drsGroupName,
        [Parameter (Mandatory = $true)] [String]$drsGroupVMs
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain -ErrorAction SilentlyContinue
        if ($vcenter) {
            Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
            if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
                $cluster = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }).clusters.id) }).Name

                $drsGroupExists = (Get-Cluster -Name $cluster | Get-DrsClusterGroup | Where-Object {$_.Name -eq $drsGroupName})
                if ($drsGroupExists) {
                    Write-Warning "The vSphere DRS Group '$drsGroupName' already exists"
                }
                else {
                    $vmNames = $drsGroupVMs.split(",")
                    $vms = foreach ($name in $vmNames) { Get-VM -name $name -ErrorAction SilentlyContinue }
                    New-DrsClusterGroup -Cluster $cluster -VM $vms -Name $drsGroupName | Out-Null
                    $drsGroupExists = (Get-Cluster -Name $cluster | Get-DrsClusterGroup | Where-Object {$_.Name -eq $drsGroupName})
                    if ($drsGroupExists) {
                        Write-Output "Created vSphere DRS Group '$drsGroupName' in vCenter Server '$($vcenter.fqdn)' Successfully"
                    }
                    else {
                        Write-Error "Creating vSphere DRS Group '$drsGroupName' in vCenter Server '$($vcenter.fqdn)' Failed, Please Retry"
                    }
                }
                Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
            }
            else {
                Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error "Workload domain name does not exist in SDDC Manager"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-ClusterGroup

Function Add-VmStartupRule {
    <#
    	.SYNOPSIS
    	Creates a VM to VM DRS rule

    	.DESCRIPTION
    	The Add-VmStartupRule cmdlet creates a vSphere DRS Virtual Machine to Virtual Machine startup rule. The cmdlet connects to SDDC Manager using the -server,
        -user, and -password values to retrive the vCenter Server details from its inventory and then:
        - Verifies that that the Virtual Machine to Virtual Machine startup rule does not already exist
        - Creates the vSphere DRS Virtual Machine to Virtual Machine startup rule

    	.EXAMPLE
    	Add-VmStartupRule -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -ruleName vm-vm-rule-wsa-vra -vmGroup sfo-m01-vm-group-wsa -dependOnVmGroup sfo-m01-vm-group-vra
    	This example shows how to create a vSphere DRS Cluster group in the vCenter Server of the sfo-m01 workload domain
  	#>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$ruleName,
        [Parameter (Mandatory = $true)] [String]$vmGroup,
        [Parameter (Mandatory = $true)] [String]$dependOnVmGroup
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain -ErrorAction SilentlyContinue
        if ($vcenter) {
            Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
            if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
                $cluster = (Get-VCFCluster | Where-Object { $_.id -eq ((Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }).clusters.id) }).Name
                $vmGroupExists = (Get-Cluster -Name $cluster | Get-DrsClusterGroup | Where-Object {$_.Name -eq $vmGroup})
                if ($vmGroupExists) {
                    $dependOnVmGroupExists = (Get-Cluster -Name $cluster | Get-DrsClusterGroup | Where-Object {$_.Name -eq $dependOnVmGroup})
                    if ($dependOnVmGroupExists) {
                        $ruleNameExists = Get-DrsVmToVmGroup -Cluster $cluster -Name $ruleName
                        if ($ruleNameExists) {
                            Write-Warning "The vSphere DRS Virtual Machine to Virtual Machine Group '$ruleName' already exists"
                        }
                        else {
                            Add-DrsVmToVmGroup -name $ruleName -vmGroup $vmGroup -dependOnVmGroup $dependOnVmGroup -Enabled -cluster $cluster | Out-Null
                            Start-Sleep 5
                            $ruleNameExists = Get-DrsVmToVmGroup -Cluster $cluster -Name $ruleName
                            if ($ruleNameExists) {
                                Write-Output "Created the vSphere DRS Virtual Machine to Virtual Machine Group '$ruleName' Successfully"
                            }
                            else {
                                Write-Error "Creating the vSphere DRS Virtual Machine to Virtual Machine Group '$ruleName' Failed, Please Retry"
                            }
                        }
                    }
                    else {
                        Write-Error "The vSphere DRS Group '$dependOnVmGroup' (VM Group to start after dependency) not found in vCenter Server inventory, create and try again" 
                    }
                }
                else {
                    Write-Error "The vSphere DRS Group '$vmGroup' (VM Group to start first) not found in vCenter Server inventory, create and try again" 
                }
                Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
            }
            else {
                Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error "Workload domain name does not exist in SDDC Manager"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-VmStartupRule

Function Move-VMtoFolder {
    <#
    	.SYNOPSIS
    	Moves VMs to a folder

    	.DESCRIPTION
    	The Move-VMtoFolder cmdlet moves the Virtual Machines to a folder. The cmdlet connects to SDDC Manager using the -server, -user, and -password values
        to retrive the vCenter Server details from its inventory and then:
        - Verifies that the folder provided exists in the vCenter Server inventory
        - Moves the virtual machines pprovided in the -vmlist parameter

    	.EXAMPLE
    	Move-VMtoFolder -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -vmList "xreg-wsa01a,xreg-wsa01b,xreg-wsa01c" -folder xinst-m01-fd-wsa
    	This example shows how to move a list of virtual machines to a new folder
  	#>

    Param (
        [Parameter (Mandatory = $true)] [String]$server,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$pass,
        [Parameter (Mandatory = $true)] [String]$domain,
        [Parameter (Mandatory = $true)] [String]$vmList,
        [Parameter (Mandatory = $true)] [String]$folder
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain -ErrorAction SilentlyContinue
        if ($vcenter) {
            Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
            if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
                if (Get-Folder | Where-Object {$_.Name -eq $folder}) {
                    $vmNames = $vmList.split(",")
                    foreach ($vm in $vmNames) { Get-VM -Name $vm | Move-VM -InventoryLocation (Get-Folder | Where-Object {$_.Name -eq $folder}) | Out-Null }
                    Write-Output "Virtual Machines '$vmList' relocated to folder '$folder' in vCenter Server '$($vcenter.fqdn)' Successfully"
                }
                else {
                    Write-Error "Folder with name '$folder' not found in vCenter Server '$($vcenter.fqdn)'"
                }
                Disconnect-VIServer $vcenter.fqdn -Confirm:$false -WarningAction SilentlyContinue
            }
            else {
                Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
            }
        }
        else {
            Write-Error "Workload domain name does not exist in SDDC Manager"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Move-VMtoFolder

Function Import-vRSLCMLockerCertificate {
    <#
        .SYNOPSIS
        Add a certificate to the vRSLCM locker

        .DESCRIPTION
        The Import-vRSLCMLockerCertificate cmdlet imports a PEM encoded chain file to the vRSLCM locker. The cmdlet connects to SDDC Manager using the -server, -user, and -password values
        to retrive the vRSLCM details from its inventory and then:
        - Verifies that the certificate doesnt already exist
        - imports the certificate chain

        .EXAMPLE
        Import-vRSLCMLockerCertificate -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -certificateAlias "xint-vrops01" -certificatePassphrase "VMw@re1!"
        This example gets the details of a certificate based on the vmid
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$certificateAlias,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$certificatePassphrase,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$certChainPath
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("certChainPath")) {
            $certChainPath = Get-ExternalFileName -title "Select the Certificate Chain PEM File (.pem)" -fileType "pem" -location "default"
        }
        else {
            if (!(Test-Path -Path $certChainPath)) {
                Write-Error  "Certificate Chain '$certChainPath' File Not Found"
                Break
            }
        }

        $vrslcm = Get-vRSLCMServerDetail -fqdn $server -username $user -password $pass
        Request-vRSLCMToken -fqdn $vrslcm.fqdn -username $vrslcm.adminUser -password $vrslcm.adminPass | Out-Null
        if (!(Get-vRSLCMLockerCertificate | Where-Object {$_.alias -Match $certificateAlias})) {
            if ($PsBoundParameters.ContainsKey("certificatePassphrase")) {
                $lockerCert = Add-vRSLCMLockerCertificate -vrslcmFQDN $vrslcm.fqdn -certificateAlias $certificateAlias -certificatePassphrase $certificatePassphrase -certChainPath $certChainPath
            }
            else {
                $lockerCert = Add-vRSLCMLockerCertificate -vrslcmFQDN $vrslcm.fqdn -certificateAlias $certificateAlias -certChainPath $certChainPath
            }
            if ((Get-vRSLCMLockerCertificate | Where-Object {$_.alias -Match $certificateAlias})) {
                Write-Output "Certificate with alias $certificateAlias imported to the locker successfully"
            }
            else {
                Write-Error "Certificate with alias $certificateAlias failed to import to the locker"
            }
        }
        else {
            Write-Warning "Certificate with alias $certificateAlias already exists in the locker"
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Import-vRSLCMLockerCertificate

Function New-vRSLCMLockerPassword {
    <#
        .SYNOPSIS
        Add a password to the vRSLCM locker

        .DESCRIPTION
        The New-vRSLCMLockerPassword cmdlet adds a password to the vRSLCM locker. The cmdlet connects to SDDC Manager using the -server, -user, and -password values
        to retrive the vRSLCM details from its inventory and then:
        - Verifies that the password doesnt already exist
        - Adds the password to the locker

        .EXAMPLE
        New-vRSLCMLockerPassword -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -alias xint-vrops01-admin -password VMw@re1! -description "vRealize Operations Admin" -userName xint-vrops01-admin
        This example adds the password
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$alias,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$description,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$userName
    )

    Try {
        $vrslcm = Get-vRSLCMServerDetail -fqdn $server -username $user -password $pass
        Request-vRSLCMToken -fqdn $vrslcm.fqdn -username $vrslcm.adminUser -password $vrslcm.adminPass | Out-Null
        if (!(Get-vRSLCMLockerPassword | Where-Object {$_.alias -Match $alias})) {
            if ($PsBoundParameters.ContainsKey("description")) {
                $lockerPassword = Add-vRSLCMLockerPassword -alias $alias -password $password -description $description -userName $userName
            }
            else {
                $lockerPassword = Add-vRSLCMLockerPassword -alias $alias -password $password -userName $userName
            }
            if ((Get-vRSLCMLockerPassword | Where-Object {$_.alias -Match $alias})) {
                Write-Output "Password with alias $alias added to the locker successfully"
            }
            else {
                Write-Error "Password with alias $alias failed to add to the locker"
            }
        }
        else {
            Write-Warning "Password with alias $alias already exists in the locker"
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-vRSLCMLockerPassword

Function New-vRSLCMLockerLicense {
    <#
        .SYNOPSIS
        Add a license to the vRSLCM locker

        .DESCRIPTION
        The New-vRSLCMLockerLicense cmdlet adds a license to the vRSLCM locker. The cmdlet connects to SDDC Manager using the -server, -user, and -password values
        to retrive the vRSLCM details from its inventory and then:
        - Verifies that the license doesnt already exist
        - Adds the license to the locker

        .EXAMPLE
        New-vRSLCMLockerLicense -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -alias "vRealize Automation" -license "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
        This example adds the password
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$alias,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$license
    )

    Try {
        $vrslcm = Get-vRSLCMServerDetail -fqdn $server -username $user -password $pass
        Request-vRSLCMToken -fqdn $vrslcm.fqdn -username $vrslcm.adminUser -password $vrslcm.adminPass | Out-Null
        if (!(Get-vRSLCMLockerLicense | Where-Object {$_.key -Like $key})) {
            if (!(Get-vRSLCMLockerLicense | Where-Object {$_.alias -Like $alias})) {
                $lockerLicense = Add-vRSLCMLockerLicense -alias $alias -license $license
                Start-Sleep 3
                if ((Get-vRSLCMLockerLicense | Where-Object {$_.key -Like $license})) {
                    Write-Output "License with alias $alias added to the locker successfully"
                }
                else {
                    Write-Error "License with alias $alias failed to add to the locker"
                }
            }
            else {
                Write-Warning "License with serial key $license already exists in the locker"
            }
        }
        else {
            Write-Warning "License with alias $alias already exists in the locker"
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-vRSLCMLockerLicense

Function Add-VmGroup {
    <#
		.SYNOPSIS
    	Add a VM Group

    	.DESCRIPTION
    	The Add-VmGroup cmdlet adds a Virtual Machine to an existing VM Group.
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values and then:
        - Verifies a connection has been made to the vCenter Server
        - Verifies that the the VM Group provided exists and that its a VM Group not a VM Host Group
        - Adds the Virtual Machines provided using -vmList

        .EXAMPLE
    	Add-VmGroup -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -name "primary_az_vmgroup" -vmList "xint-vra01a,xint-vra01b,xint-vra01c"
        This example adds the vRealize Automation cluster VMs to the VM Group called primary_az_vmgroup
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$name,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vmList
    )

    Try {
        Request-VCFToken -fqdn $server -Username $user -Password $pass | Out-Null
        if ($accessToken) {
            $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain
            Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -Pass $vcenter.ssoAdminPass | Out-Null
            if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
                $vmGroupExists = Get-DrsClusterGroup -Server $vcenter.fqdn -Name $name
                if ($vmGroupExists.GroupType -eq "VMGroup") {
                    $vmNames = $vmList.split(",")
                    foreach ($vm in $vmNames) { Set-DrsClusterGroup -VM $vm -Server $vcenter.fqdn -DrsClusterGroup (Get-DrsClusterGroup | Where-Object {$_.Name -eq $name} -WarningAction SilentlyContinue -ErrorAction Ignore) -Add | Out-Null }
                    Write-Output "Systems '$vmList' Added to VM/Host Group '$name' in vCenter Server '$($vcenter.fqdn)' Successfully"
                }
                else {
                    Write-Error  "The DRS Cluster Group '$name' does not exist or is not a VM Group"
                }
            }
            else {
			    Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
		    }
        }
        else {
            Write-Error "Failed to obtain access token from SDDC Manager, check details provided"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-VmGroup

##########################################  E N D   O F   F U N C T I O N S  ##########################################
#######################################################################################################################


#######################################################################################################################
#####################################  S U P P O R T I N G   F U N C T I O N S   ######################################

##############################################################
#############  Begin Active Directory Functions  #############

Function Test-ADAuthentication {
    <#
        .SYNOPSIS
        Test authetication against Active Directory

        .DESCRIPTION
        The Test-ADAuthentication cmdlet tests the credentials provided against Active Directory domain

        .EXAMPLE
        Test-ADAuthentication -user svc-vsphere-ad -pass VMw@re1! -server sfo.rainpole.io -domain sfo.rainpole.io
        This example check that the svc-vsphere-ad user can authenticate to the sfo.rainpole.io domain
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $false)] [String]$server,
        [Parameter (Mandatory = $false)] [String]$domain = $env:USERDOMAIN
    )

    Try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $contextType = [System.DirectoryServices.AccountManagement.ContextType]::Domain
        $argumentList = New-Object -TypeName "System.Collections.ArrayList"
        $null = $argumentList.Add($contextType)
        $null = $argumentList.Add($domain)
        if ($null -ne $server) {
            $argumentList.Add($server)
        }
        $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext -ArgumentList $argumentList -ErrorAction SilentlyContinue
        if ($null -eq $principalContext) {
            Write-Error "$domain\$user - AD Authentication Failed"
        }
        if ($principalContext.ValidateCredentials($user, $pass)) {
            Write-Output "$domain\$user - AD Authentication Successful"
        }
        else {
            Write-Error "$domain\$user - AD Authentication Failed"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Test-ADAuthentication

Function Get-ADPrincipalGuid {
    <#
        .SYNOPSIS
        Get principal GUID details

        .DESCRIPTION
        The Get-ADPrincipalGuid cmdlet retrieves the GUID details for an active directory user or group Active Directory domain

        .EXAMPLE
        Get-ADPrincipalGuid -domain sfo.rainple.io -user svc-vsphere-ad -pass VMw@re1! -principal gg-sso-admin
        This example retrives the details for th gg-sso-admin domain
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$principal
    )

    Try {
        $checkAdAuthentication = Test-ADAuthentication -user $user -pass $pass -server $domain -domain $domain
        if ($checkAdAuthentication -contains "2") {
            $securePassword = ConvertTo-SecureString -String $pass -AsPlainText -Force
            $creds = New-Object System.Management.Automation.PSCredential ($user, $securePassword)
            $nsxAdminGroupObject = (Get-ADGroup -Server $domain -Credential $creds -Filter { SamAccountName -eq $principal })
            $nsxAdminGroupObject
        }
        else {
            Write-Error "Domain User $user Authentication Failed"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Get-ADPrincipalGuid

##############  End Active Directory Functions  ##############
##############################################################


##############################################################
#############  Begin Cloud Foundation Functions  #############

Function Get-vCenterServerDetail {
    Param (
        [Parameter (Mandatory = $false)] [String]$server,
        [Parameter (Mandatory = $false)] [String]$user,
        [Parameter (Mandatory = $false)] [String]$pass,
        [Parameter (Mandatory = $false)] [ValidateSet("MANAGEMENT", "VI")][String]$domainType,
        [Parameter (Mandatory = $false)] [String]$domain
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("user") -or (!$PsBoundParameters.ContainsKey("pass"))) {
            # Request Credentials
            $creds = Get-Credential
            $user = $creds.UserName.ToString()
            $pass = $creds.GetNetworkCredential().password
        }
        if (!$PsBoundParameters.ContainsKey("server")) {
            $server = Read-Host "SDDC Manager access token not found. Please enter the SDDC Manager FQDN, e.g., sfo-vcf01.sfo.rainpole.io"
        }
        Request-VCFToken -fqdn $server -Username $user -Password $pass | Out-Null

        if ($accessToken) {
            if ($PsBoundParameters.ContainsKey("domainType")) {
                # Dynamically build vCenter Server details based on Cloud Foundation domain type
                $vcfWorkloadDomainDetails = Get-VCFWorkloadDomain | Where-Object { $_.type -eq $domainType }
            }
            if ($PsBoundParameters.ContainsKey("domain")) {
                # Dynamically build vCenter Server details based on Cloud Foundation domain name
                $vcfWorkloadDomainDetails = Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }
            }
            if ($vcfWorkloadDomainDetails) {
                $vcenterServerDetails = Get-VCFvCenter | Where-Object { $_.id -eq $($vcfWorkloadDomainDetails.vcenters.id) }
                $vcenterCredentialDetails = Get-VCFCredential | Where-Object { $_.resource.resourceId -eq $($vcenterServerDetails.id) }
                $pscCredentialDetails = Get-VCFCredential | Where-Object { $_.resource.resourceType -eq "PSC" }
                $vcenterServer = New-Object -TypeName psobject
                $vcenterServer | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $vcenterServerDetails.fqdn
                $vcenterServer | Add-Member -notepropertyname 'vmName' -notepropertyvalue $vcenterServerDetails.fqdn.Split(".")[0]
                $vcfDetail = Get-VCFManager
                if ( ($vcfDetail.version).Split("-")[0] -gt "4.1.0.0") {
                    $vcenterServer | Add-Member -notepropertyname 'ssoAdmin' -notepropertyvalue ($pscCredentialDetails | Where-Object { ($_.credentialType -eq "SSO" -and $_.accountType -eq "SYSTEM") }).username
                    $vcenterServer | Add-Member -notepropertyname 'ssoAdminPass' -notepropertyvalue ($pscCredentialDetails | Where-Object { ($_.credentialType -eq "SSO" -and $_.accountType -eq "SYSTEM") }).password
                }
                else {
                    $vcenterServer | Add-Member -notepropertyname 'ssoAdmin' -notepropertyvalue ($pscCredentialDetails | Where-Object { ($_.credentialType -eq "SSO" -and $_.accountType -eq "USER") }).username
                    $vcenterServer | Add-Member -notepropertyname 'ssoAdminPass' -notepropertyvalue ($pscCredentialDetails | Where-Object { ($_.credentialType -eq "SSO" -and $_.accountType -eq "USER") }).password
                }
                $vcenterServer | Add-Member -notepropertyname 'root' -notepropertyvalue ($vcenterCredentialDetails | Where-Object { ($_.credentialType -eq "SSH" -and $_.accountType -eq "USER") }).username
                $vcenterServer | Add-Member -notepropertyname 'rootPass' -notepropertyvalue ($vcenterCredentialDetails | Where-Object { ($_.credentialType -eq "SSH" -and $_.accountType -eq "USER") }).password
                $vcenterServer
            }
            else {
                Write-Error "Workload domainType or domain name does not exist"
                Break
            }
        }
        else {
            Write-Error "Failed to obtain access token from SDDC Manager, check details provided"
            Break
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Get-vCenterServerDetail

Function Get-NsxtServerDetail {
    Param (
        [Parameter (Mandatory = $false)] [String]$fqdn,
        [Parameter (Mandatory = $false)] [String]$username,
        [Parameter (Mandatory = $false)] [String]$password,
        [Parameter (Mandatory = $false)] [String]$domain,
        [Parameter( Mandatory = $false)] [ValidateSet("MANAGEMENT", "VI")] [String]$domainType,
		[Parameter (Mandatory = $false)] [switch]$listNodes = $false
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("username") -or (!$PsBoundParameters.ContainsKey("password"))) {
            # Request Credentials
            $creds = Get-Credential
            $username = $creds.UserName.ToString()
            $password = $creds.GetNetworkCredential().password
        }
        if (!$PsBoundParameters.ContainsKey("fqdn")) {
            $fqdn = Read-Host "SDDC Manager access token not found. Please enter the SDDC Manager FQDN, e.g., sfo-vcf01.sfo.rainpole.io"
        }
        Request-VCFToken -fqdn $fqdn -Username $username -Password $password | Out-Null

        if ($accessToken) {
            if ($PsBoundParameters.ContainsKey("domainType")) {
                # Dynamically build vCenter Server details based on Cloud Foundation domain type
                $vcfWorkloadDomainDetails = Get-VCFWorkloadDomain | Where-Object { $_.type -eq $domainType }
            }
            if ($PsBoundParameters.ContainsKey("domain")) {
                # Dynamically build vCenter Server details based on Cloud Foundation domain name
                $vcfWorkloadDomainDetails = Get-VCFWorkloadDomain | Where-Object { $_.name -eq $domain }
            }
            if ($vcfWorkloadDomainDetails) {
                $nsxtServerDetails = Get-VCFNsxtcluster | Where-Object { $_.id -eq $($vcfWorkloadDomainDetails.nsxtCluster.id) }
                $nsxtCreds = Get-VCFCredential | Where-Object { $_.resource.resourceId -eq $($nsxtServerDetails.id) }

                $nsxtCluster = New-Object -TypeName PSCustomObject
                $nsxtCluster | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $nsxtServerDetails.vipFqdn
                $nsxtCluster | Add-Member -notepropertyname 'adminUser' -notepropertyvalue ($nsxtCreds | Where-Object { ($_.credentialType -eq "API" -and $_.accountType -eq "SYSTEM") }).username
                $nsxtCluster | Add-Member -notepropertyname 'adminPass' -notepropertyvalue ($nsxtCreds | Where-Object { ($_.credentialType -eq "API" -and $_.accountType -eq "SYSTEM") }).password
                $nsxtCluster | Add-Member -notepropertyname 'rootUser' -notepropertyvalue ($nsxtCreds | Where-Object { ($_.credentialType -eq "SSH" -and $_.accountType -eq "SYSTEM") }).username
                $nsxtCluster | Add-Member -notepropertyname 'rootPass' -notepropertyvalue ($nsxtCreds | Where-Object { ($_.credentialType -eq "SSH" -and $_.accountType -eq "SYSTEM") }).password
                if ($listNodes) {
					$nsxtCluster | Add-Member -notepropertyname 'nodes' -notepropertyvalue $nsxtServerDetails.nodes
				}
				$nsxtCluster
            }
            else {
                Write-Error "Workload domainType or domain name does not exist"
                Break
            }
        }
        else {
            Write-Error "Failed to obtain access token from SDDC Manager, check details provided"
            Break
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Get-NsxtServerDetail

Function Get-vRSLCMServerDetail {
    Param (
        [Parameter (Mandatory = $false)] [String]$fqdn,
        [Parameter (Mandatory = $false)] [String]$username,
        [Parameter (Mandatory = $false)] [String]$password
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("username") -or (!$PsBoundParameters.ContainsKey("password"))) {
            # Request Credentials
            $creds = Get-Credential
            $username = $creds.UserName.ToString()
            $password = $creds.GetNetworkCredential().password
        }
        if (!$PsBoundParameters.ContainsKey("fqdn")) {
            $fqdn = Read-Host "SDDC Manager access token not found. Please enter the SDDC Manager FQDN, e.g., sfo-vcf01.sfo.rainpole.io"
        }
        Request-VCFToken -fqdn $fqdn -Username $username -Password $password | Out-Null

        if ($accessToken) {
                # Get vRSLCM Server Details
                $vRSLCMFQDN = Get-VCFvRSLCM
                $vRSLCMCreds = Get-VCFCredential -resourceName $vRSLCMFQDN.fqdn
                $vrslcmDetails = New-Object -TypeName PSCustomObject
                $vrslcmDetails | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $vRSLCMFQDN.fqdn
                $vrslcmDetails | Add-Member -notepropertyname 'adminUser' -notepropertyvalue ($vRSLCMCreds | Where-Object { ($_.credentialType -eq "API" -and $_.accountType -eq "SYSTEM") }).username
                $vrslcmDetails | Add-Member -notepropertyname 'adminPass' -notepropertyvalue ($vRSLCMCreds | Where-Object { ($_.credentialType -eq "API" -and $_.accountType -eq "SYSTEM") }).password
                $vrslcmDetails
            }
        else {
            Write-Error "Failed to obtain access token from SDDC Manager, check details provided"
            Break
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Get-vRSLCMServerDetail

Function Get-WSAServerDetail {
    Param (
        [Parameter (Mandatory = $false)] [String]$fqdn,
        [Parameter (Mandatory = $false)] [String]$username,
        [Parameter (Mandatory = $false)] [String]$password
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("username") -or (!$PsBoundParameters.ContainsKey("password"))) {
            # Request Credentials
            $creds = Get-Credential
            $username = $creds.UserName.ToString()
            $password = $creds.GetNetworkCredential().password
        }
        if (!$PsBoundParameters.ContainsKey("fqdn")) {
            $fqdn = Read-Host "SDDC Manager access token not found. Please enter the SDDC Manager FQDN, e.g., sfo-vcf01.sfo.rainpole.io"
        }
        Request-VCFToken -fqdn $fqdn -Username $username -Password $password | Out-Null
        
        if ($accessToken) {
                # Get WSA Server Details
                $wsaFQDN = Get-VCFWSA
                #$wsaCreds = Get-VCFCredential -resourceName $wsaFQDN.fqdn
                $wsaDetails = New-Object -TypeName PSCustomObject
                $wsaDetails | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $wsaFQDN.elements.nodes.fqdn
                $wsaDetails | Add-Member -notepropertyname 'loadBalancerIpAddress' -notepropertyvalue $wsaFQDN.elements.loadBalancerIpAddress
                $wsaDetails | Add-Member -notepropertyname 'node1IpAddress' -notepropertyvalue $wsaFQDN.elements.nodes.ipAddress[0]
                $wsaDetails | Add-Member -notepropertyname 'node2IpAddress' -notepropertyvalue $wsaFQDN.elements.nodes.ipAddress[1]
                $wsaDetails | Add-Member -notepropertyname 'node3IpAddress' -notepropertyvalue $wsaFQDN.elements.nodes.ipAddress[2]
                $wsaDetails
            }
        else {
            Write-Error "Failed to obtain access token from SDDC Manager, check details provided"
            }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Get-WSAServerDetail

Function Get-vRAServerDetail {
    Param (
        [Parameter (Mandatory = $false)] [String]$fqdn,
        [Parameter (Mandatory = $false)] [String]$username,
        [Parameter (Mandatory = $false)] [String]$password
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("username") -or (!$PsBoundParameters.ContainsKey("password"))) {
            # Request Credentials
            $creds = Get-Credential
            $username = $creds.UserName.ToString()
            $password = $creds.GetNetworkCredential().password
        }
        if (!$PsBoundParameters.ContainsKey("fqdn")) {
            $fqdn = Read-Host "SDDC Manager access token not found. Please enter the SDDC Manager FQDN, e.g., sfo-vcf01.sfo.rainpole.io"
        }
        Request-VCFToken -fqdn $fqdn -Username $username -Password $password | Out-Null
        
        if ($accessToken) {
                # Get vRSLCM Server Details
                $vraFQDN = Get-VCFvRA
                #$vraCreds = Get-VCFCredential -resourceName $vraFQDN.fqdn
                $vraDetails = New-Object -TypeName PSCustomObject
                $vraDetails | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $vraFQDN.elements.nodes.fqdn
                $vraDetails | Add-Member -notepropertyname 'loadBalancerIpAddress' -notepropertyvalue $vraFQDN.elements.loadBalancerIpAddress
                $vraDetails | Add-Member -notepropertyname 'node1IpAddress' -notepropertyvalue $vraFQDN.elements.nodes.ipAddress[0]
                $vraDetails | Add-Member -notepropertyname 'node2IpAddress' -notepropertyvalue $vraFQDN.elements.nodes.ipAddress[1]
                $vraDetails | Add-Member -notepropertyname 'node3IpAddress' -notepropertyvalue $vraFQDN.elements.nodes.ipAddress[2]
                $vraDetails
            }
        else {
            Write-Error "Failed to obtain access token from SDDC Manager, check details provided"
            Break
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Get-vRAServerDetail

Function Get-vROPsServerDetail {
    Param (
        [Parameter (Mandatory = $false)] [String]$fqdn,
        [Parameter (Mandatory = $false)] [String]$username,
        [Parameter (Mandatory = $false)] [String]$password
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("username") -or (!$PsBoundParameters.ContainsKey("password"))) {
            # Request Credentials
            $creds = Get-Credential
            $username = $creds.UserName.ToString()
            $password = $creds.GetNetworkCredential().password
        }
        if (!$PsBoundParameters.ContainsKey("fqdn")) {
            $fqdn = Read-Host "SDDC Manager access token not found. Please enter the SDDC Manager FQDN, e.g., sfo-vcf01.sfo.rainpole.io"
        }
        Request-VCFToken -fqdn $fqdn -Username $username -Password $password | Out-Null
        
        if ($accessToken) {
            # Get vRSLCM Server Details
            $vropsFQDN = Get-VCFvROPs
            $vropsDetails = New-Object -TypeName PSCustomObject
            $vropsDetails | Add-Member -notepropertyname 'fqdn' -notepropertyvalue $vropsFQDN.elements.nodes.fqdn
            $vropsDetails | Add-Member -notepropertyname 'loadBalancerIpAddress' -notepropertyvalue $vropsFQDN.elements.loadBalancerIp
            $vropsNode1FQDN = $vropsFQDN.elements.nodes.fqdn[0]
            $vropsNode1IP = [System.Net.Dns]::GetHostAddresses("$vropsNode1FQDN").IPAddressToString
            $vropsDetails | Add-Member -notepropertyname 'node1IpAddress' -notepropertyvalue $vropsNode1IP
            $vropsNode2FQDN = $vropsFQDN.elements.nodes.fqdn[1]
            $vropsNode2IP = [System.Net.Dns]::GetHostAddresses("$vropsNode2FQDN").IPAddressToString
            $vropsDetails | Add-Member -notepropertyname 'node2IpAddress' -notepropertyvalue $vropsNode2IP
            $vropsNode3FQDN = $vropsFQDN.elements.nodes.fqdn[2]
            $vropsNode3IP = [System.Net.Dns]::GetHostAddresses("$vropsNode3FQDN").IPAddressToString
            $vropsDetails | Add-Member -notepropertyname 'node3IpAddress' -notepropertyvalue $vropsNode3IP
            $vropsDetails
        }
        else {
            Write-Error "Failed to obtain access token from SDDC Manager, check details provided"
            Break
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Get-vROPsServerDetail


##############  End Cloud Foundation Functions  ##############
##############################################################


##############################################################
##################  Begin vSphere Functions  #################

Function Request-VCToken {
    <#
        .SYNOPSIS
        Connects to the specified vCenter Server API and stores the credentials in a base64 string

        .DESCRIPTION
        The Request-VCToken cmdlet connects to the specified vCenter Server and stores the credentials
        in a base64 string. It is required once per session before running all other cmdlets

        .EXAMPLE
        Request-VCToken -fqdn sfo-m01-vc01.sfo.rainpole.io -username administrator@vsphere.local -password VMw@re1!
        This example shows how to connect to the vCenter Server API
      #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$password
    )

    if ( -not $PsBoundParameters.ContainsKey("username") -or ( -not $PsBoundParameters.ContainsKey("password"))) {
        $creds = Get-Credential # Request Credentials
        $username = $creds.UserName.ToString()
        $password = $creds.GetNetworkCredential().password
    }

    $Global:vcenterFqdn = $fqdn

    $vcenterHeader = @{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+$password))}
    $contentType = "application/json"
    $uri = "https://$vcenterFqdn/api/session"

    Try {
        # Checking authentication with vCenter Server API
        if ($PSEdition -eq 'Core') {
            $Global:vcToken = Invoke-RestMethod -Uri $uri -Headers $vcenterHeader -Method POST -ContentType $contentType -SkipCertificateCheck # PS Core has -SkipCertificateCheck implemented
        }
        else {
            $Global:vcToken = Invoke-RestMethod -Uri $uri -Headers $vcenterHeader -Method POST -ContentType $contentType
        }
        if ($vcToken) {
            Write-Output "Successfully connected to the vCenter Server API: $vcenterFqdn"
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Request-VCToken

Function Get-VCVersion {
    <#
        .SYNOPSIS
        Get the version

        .DESCRIPTION
        The Get-VCVersion cmdlet gets the version of the vCenter Server

        .EXAMPLE
        Get-VCVersion
        This example gets the version of the vCenter Server
    #>

    Try {
        $vcenterHeader = @{"vmware-api-session-id" = "$vcToken"}
        $uri = "https://$vcenterFqdn/api/appliance/system/version"

        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vcenterHeader
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-VCVersion

Function Get-VCConfigurationNTP {
    <#
    	.SYNOPSIS
    	Get NTP configuration

    	.DESCRIPTION
    	The Get-VCConfigurationNTP cmdlet gets the NTP configuration of vCenter Server

    	.EXAMPLE
    	Get-VCConfigurationNTP
    	This example gets the NTP configuration of the vCenter Server
  	#>

    Try {
        $vcenterHeader = @{"vmware-api-session-id" = "$vcToken"}
        $uri = "https://$vcenterFqdn/api/appliance/ntp"

        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vcenterHeader
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-VCConfigurationNTP

Function Get-VCConfigurationDNS {
    <#
        .SYNOPSIS
        Get DNS configuration

        .DESCRIPTION
        The Get-VCConfigurationDNS cmdlet gets the DNS configuration of vCenter Server

        .EXAMPLE
        Get-VCConfigurationDNS
        This example gets the DNS configuration of the vCenter Server
    #>

    Try {
        $vcenterHeader = @{"vmware-api-session-id" = "$vcToken"}
        $uri = "https://$vcenterFqdn/api/appliance/networking/dns/servers"

        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vcenterHeader
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-VCConfigurationDNS

Function Get-VCPasswordPolicy {
    <#
    .SYNOPSIS
        Get the global password policy.

        .DESCRIPTION
        The Get-VCPasswordPolicy cmdlet gets global password policy for the vCenter Server

        .EXAMPLE
        Get-VCPasswordPolicy
        This example gets the global password policy of the vCenter Server
    #>

    Try {
        $vcenterHeader = @{"vmware-api-session-id" = "$vcToken"}
        $uri = "https://$vcenterFqdn/api/appliance/local-accounts/global-policy"

        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vcenterHeader
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-VCPasswordPolicy

Function Set-VCPasswordPolicy {
    <#
        .SYNOPSIS
        Set the global password policy

        .DESCRIPTION
        The Set-VCPasswordPolicy cmdlet configures the global password policy for the vCenter Server

        .EXAMPLE
        Set-VCPasswordPolicy -maxDays 120 -minDays 1 -warnDays 14
        This example configures the global password policy of the vCenter Server
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$maxDays,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$minDays,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$warnDays
    )

    Try {
        $vcenterHeader = @{"vmware-api-session-id" = "$vcToken"}
        $vcenterHeader.Add("Content-Type", "application/json")
        $uri = "https://$vcenterFqdn/api/appliance/local-accounts/global-policy"
        $body = '{ "max_days": '+$maxDays+', "min_days": '+$minDays+', "warn_days": '+$warnDays+' }'

        $response = Invoke-RestMethod -Method PUT -Uri $uri -Headers $vcenterHeader -Body $body
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-VCPasswordPolicy

Function Get-VCPasswordExpiry {
    <#
    .SYNOPSIS
		Get the vcenter password expiry date.

        .DESCRIPTION
        The Get-VCPasswordPolicy cmdlet gets password expiration settings for the vCenter Server root account

        .EXAMPLE
        Get-VCPasswordExpiry
        This example gets the password policy of the vCenter Server
    #>

    Try {
        $uri = "https://$currentvCenterServer"+":5480/rest/appliance/local-accounts/root"
        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vcAdminHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-VCPasswordExpiry

Function Set-VCPasswordExpiry {
    <#
        .SYNOPSIS
        Set the vcenter password expiry date

        .DESCRIPTION
        The Set-VCPasswordExpiry cmdlet configures password expiration settings for the vCenter Server root account

        .EXAMPLE
        Set-VCPasswordExpiry -passwordExpires $true -email "admin@rainpole.io" -maxDaysBetweenPasswordChange 91
        This example configures the configures password expiration settings for the vCenter Server root account

		Set-VCPasswordExpiry -passwordExpires $false
        This example configures the configures password expiration settings for the vCenter Server root account to never expire
    #>

    Param (
        [Parameter (Mandatory = $false, ParameterSetName = 'neverexpire')] [Parameter (Mandatory = $true, ParameterSetName = 'expire')] [ValidateNotNullOrEmpty()] [Bool]$passwordExpires,
        [Parameter (Mandatory = $true, ParameterSetName = 'expire')] [ValidateNotNullOrEmpty()] [String]$email,
        [Parameter (Mandatory = $true, ParameterSetName = 'expire')] [ValidateNotNullOrEmpty()] [String]$maxDaysBetweenPasswordChange
    )

    Try {
        $uri = "https://$currentvCenterServer"+":5480/rest/appliance/local-accounts/root"

		if ($passwordExpires) {
			$body = '{"config":{"password_expires": "'+ $passwordExpires +'", "email": "'+ $email+ '", "max_days_between_password_change": "' + $maxDaysBetweenPasswordChange + '" }}'
		}
        else {
			$body = '{"config":{"password_expires": "'+ $passwordExpires + '"}}'
		}
        $response = Invoke-RestMethod -Method PATCH -Uri $uri -Headers $vcAdminHeaders -Body $body
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-VCPasswordExpiry

Function Add-GlobalPermission {
    <#
    	.SYNOPSIS
    	Script to add vSphere Global Permission

    	.DESCRIPTION
    	The Add-GlobalPermission cmdlet adds a new vSphere Global Permission

        .NOTES
        Author:     William Lam. Modified by Ken Gould to permit principal type (user or group) and Gary Blake to include
                    in this function
        Reference:  http://www.virtuallyghetto.com/2017/02/automating-vsphere-global-permissions-with-powercli.html

    	.EXAMPLE
    	Add-GlobalPermission -vcServer sfo-m01-vc01.sfo.rainpole.io -username administrator@vsphewre.local -vcPassword VMware1! -user svc-vc-admins
    	This example shows how to add the Administrator global permission to a user called svc-vc-admins
  	#>

    Param (
        [Parameter (Mandatory = $true)] [String]$vcServer,
        [Parameter (Mandatory = $true)] [String]$vcUsername,
        [Parameter (Mandatory = $true)] [String]$vcPassword,
        [Parameter (Mandatory = $true)] [String]$user,
        [Parameter (Mandatory = $true)] [String]$roleId,
        [Parameter (Mandatory = $true)] [String]$propagate,
        [Parameter (Mandatory = $true)] [String]$type
    )

    Try {
        $secpasswd = ConvertTo-SecureString $vcPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($vcUsername, $secpasswd)
        $mob_url = "https://$vcServer/invsvc/mob3/?moid=authorizationService&method=AuthorizationService.AddGlobalAccessControlList" # vSphere MOB URL to private enableMethods

    # Ignore SSL Warnings
    add-type -TypeDefinition  @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        $results = Invoke-WebRequest -Uri $mob_url -SessionVariable vmware -Credential $credential -Method GET # Initial login to vSphere MOB using GET and store session using $vmware variable
        # Extract hidden vmware-session-nonce which must be included in future requests to prevent CSRF error
        # Credit to https://blog.netnerds.net/2013/07/use-powershell-to-keep-a-cookiejar-and-post-to-a-web-form/ for parsing vmware-session-nonce via Powershell
        if ($results.StatusCode -eq 200) {
            $null = $results -match 'name="vmware-session-nonce" type="hidden" value="?([^\s^"]+)"'
            $sessionnonce = $matches[1]
        }
        else {
            Write-Error "Failed to login to vSphere MOB"
            exit 1
        }

        $vc_user_escaped = [uri]::EscapeUriString($user) # Escape username

        # The POST data payload must include the vmware-session-nonce variable + URL-encoded
    If ($type -eq "group") {
        $body = @"
vmware-session-nonce=$sessionnonce&permissions=%3Cpermissions%3E%0D%0A+++%3Cprincipal%3E%0D%0A++++++%3Cname%3E$vc_user_escaped%3C%2Fname%3E%0D%0A++++++%3Cgroup%3Etrue%3C%2Fgroup%3E%0D%0A+++%3C%2Fprincipal%3E%0D%0A+++%3Croles%3E$roleId%3C%2Froles%3E%0D%0A+++%3Cpropagate%3E$propagate%3C%2Fpropagate%3E%0D%0A%3C%2Fpermissions%3E
"@
    }
    else {
        $body = @"
vmware-session-nonce=$sessionnonce&permissions=%3Cpermissions%3E%0D%0A+++%3Cprincipal%3E%0D%0A++++++%3Cname%3E$vc_user_escaped%3C%2Fname%3E%0D%0A++++++%3Cgroup%3Efalse%3C%2Fgroup%3E%0D%0A+++%3C%2Fprincipal%3E%0D%0A+++%3Croles%3E$roleId%3C%2Froles%3E%0D%0A+++%3Cpropagate%3E$propagate%3C%2Fpropagate%3E%0D%0A%3C%2Fpermissions%3E
"@
    }

        $results = Invoke-WebRequest -Uri $mob_url -WebSession $vmware -Method POST -Body $body # Second request using a POST and specifying our session from initial login + body request
        if ($results.StatusCode -eq 200) {
            Write-Verbose "Successfully added global permission for: $user"
        }
        $mob_logout_url = "https://$vcServer/invsvc/mob3/logout" # Logout out of vSphere MOB
        $results = Invoke-WebRequest -Uri $mob_logout_url -WebSession $vmware -Method GET
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Add-GlobalPermission

Function Get-SsoPasswordPolicies {
    <#
    	.SYNOPSIS
    	Get vSphere Single-Sign On password policies

    	.DESCRIPTION
    	The Get-SsoPasswordPolicies cmdlet gets the vSphere Single-Sign On password policies

    	.EXAMPLE
    	Get-SsoPasswordPolicies -ssoAdminPass VMw@re1! -ssoDomain vsphere.local -vmName sfo-m01-vc01 -rootPass VMw@re1!
    	This example shows how to get vSphere Single-Sign On password policies
  	#>

    Param (
        [Parameter (Mandatory = $true)] [String]$ssoAdminPass,
        [Parameter (Mandatory = $true)] [String]$ssoDomain,
        [Parameter (Mandatory = $true)] [String]$vmName,
        [Parameter (Mandatory = $true)] [String]$rootPass
    )

    Try {
        $a, $b = $ssoDomain.split(".")
        $scriptCommand = "/opt/likewise/bin/ldapsearch -h localhost -w $ssoAdminPass -x -D `"cn=Administrator,cn=Users,dc=$a,dc=$b`" -b `"cn=password and lockout policy,dc=$a,dc=$b`" | grep vmwPassword"
        $output = Invoke-VMScript -ScriptText $scriptCommand -vm $vmName -GuestUser "root" -GuestPassword $rootPass
        $output.scriptOutput
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-SsoPasswordPolicies

Function Add-DrsVmToVmGroup {
    <#
    	.SYNOPSIS
    	Creates a vSphere VM to VM Group

    	.DESCRIPTION
    	The Add-DrsVmToVmGroup cmdlet creates a vSphere VM to VM Group

    	.EXAMPLE
    	Add-DrsVmToVmGroup -name vm-vm-rule-wsa-vra -vmGroup sfo-m01-vm-group-wsa -dependOnVmGroup sfo-m01-vm-group-vra -Enabled -cluster sfo-m01-cl01
    	This example shows how to create a vSphere VM to VM group in the vCenter Server
  	#>

    Param (
        [Parameter (Mandatory = $true)] [String]$name,
        [Parameter (Mandatory = $true)] [String]$vmGroup,
        [Parameter (Mandatory = $true)] [String]$dependOnVmGroup,
        [Parameter (Mandatory = $false)] [Switch]$enabled=$true,
        [Parameter (Mandatory = $true)] [String]$cluster
    )

    Try {
        $updateCluster = Get-Cluster | Where-Object {$_.Name -eq $cluster}

        $spec = New-Object VMware.Vim.ClusterConfigSpecEx
        $spec.RulesSpec = New-Object VMware.Vim.ClusterRuleSpec[] (1)
        $spec.RulesSpec[0] = New-Object VMware.Vim.ClusterRuleSpec
        $spec.RulesSpec[0].Operation = 'add'
        $spec.RulesSpec[0].Info = New-Object VMware.Vim.ClusterDependencyRuleInfo
        $spec.RulesSpec[0].Info.DependsOnVmGroup = $dependOnVmGroup
        $spec.RulesSpec[0].Info.VmGroup = $vmGroup
        $spec.RulesSpec[0].Info.Name = $name
        $spec.RulesSpec[0].Info.UserCreated = $true
        $spec.RulesSpec[0].Info.Enabled = $true

        $ClusterToReconfig = Get-View -Id $updateCluster.ExtensionData.MoRef
        $ClusterToReconfig.ReconfigureComputeResource_Task($spec, $true)
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Add-DrsVmToVmGroup

Function Get-DrsVmToVmGroup {
    <#
    	.SYNOPSIS
    	Gets all vSphere VM to VM Group

    	.DESCRIPTION
    	The Get-DrsVmToVmGroup cmdlet retrieves the vSphere VM to VM Group

    	.EXAMPLE
    	Get-DrsVmToVmGroup -name vm-vm-rule-wsa-vra -cluster sfo-m01-cl01
    	This example shows how to retrieve a vSphere VM to VM group in the vCenter Server
  	#>

    Param (
        [Parameter (Mandatory = $false)] [String]$name,
        [Parameter (Mandatory = $true)] [String]$cluster
    )

    Try {
        $getCluster = Get-Cluster | Where-Object {$_.Name -eq $cluster}
        if ($PsBoundParameters.ContainsKey("name")){
            $getCluster.ExtensionData.Configuration.Rule | Where-Object {$_.Name -eq $name}
        }
        else {
            $getCluster.ExtensionData.Configuration.Rule
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-DrsVmToVmGroup


##################  End vSphere Functions  ###################
##############################################################


##############################################################
###########  Begin Workspace ONE Access Functions  ###########

Function Request-WSAToken {
    <#
		.SYNOPSIS
    	Connects to the specified Workspace ONE Access instance to obtain a session token

    	.DESCRIPTION
    	The Request-WSAToken cmdlet connects to the specified Workspace ONE Access instance and requests a session token

    	.EXAMPLE
    	Request-WSAToken -fqdn sfo-wsa01.sfo.rainpole.io -username admin -password VMware1!
        This example shows how to connect to a Workspace ONE Access instance and request a session token
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass
    )

    If ( -not $PsBoundParameters.ContainsKey("user") -or ( -not $PsBoundParameters.ContainsKey("pass"))) {
        # Request Credentials
        $creds = Get-Credential
        $user = $creds.UserName.ToString()
        $pass = $creds.GetNetworkCredential().password
    }

    $Global:workSpaceOne = $fqdn

    # Validate credentials by executing an API call
    $wsaHeaders = @{"Content-Type" = "application/json" }
    $wsaHeaders.Add("Accept", "application/json; charset=utf-8")
    $uri = "https://$workSpaceOne/SAAS/API/1.0/REST/auth/system/login"
    $body = '{"username": "' + $user + '", "password": "' + $pass + '", "issueToken": "true"}'

    Try {
        # Checking against the API
        # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod $uri -Method 'POST' -Headers $wsaHeaders -Body $body -SkipCertificateCheck
            $Global:sessionToken = "HZN " + $response.sessionToken
        }
        else {
            $response = Invoke-RestMethod $uri -Method 'POST' -Headers $wsaHeaders -Body $body
            $Global:sessionToken = "HZN " + $response.sessionToken
        }
        if ($response.sessionToken) {
            Write-Output "Successfully Requested New Session Token From Workspace ONE Access instance: $fqdn"
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Request-WSAToken

Function Get-WSAConnector {
    <#
		.SYNOPSIS
    	Get connectors

    	.DESCRIPTION
    	The Get-WSAConnector cmdlets retrieves a list of connectors in Workspace ONE Access

    	.EXAMPLE
    	Get-WSAConnector
        This example retrives a list of connectors in Workspace ONE Access
  	#>

    Try {
        $wsaHeaders = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.connector+json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/connectormanagement/connectorinstances"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
        $response.items
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSAConnector

Function Get-WSADirectory {
    <#
		.SYNOPSIS
    	Get diretories

    	.DESCRIPTION
    	The Get-WSADirectory cmdlets retrieves all directories in Workspace ONE Access

    	.EXAMPLE
    	Get-WSADirectory
        This example retrives a list of directories in Workspace ONE Access
  	#>

    Try {
        $wsaHeaders = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.ad.over.ldap+json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/connectormanagement/directoryconfigs"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
        $response.items
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSADirectory

Function Get-WSADirectoryDomain {
    <#
		.SYNOPSIS
    	Get directory domains

    	.DESCRIPTION
    	The Get-WSADirectoryDomain cmdlets retrieves a list of directory domains in Workspace ONE Access

    	.EXAMPLE
    	Get-WSADirectoryDomain -directoryId a1c985d5-0eeb-4a66-bc51-11eda9321aac
        This example retrives a list of directory domains in Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [string]$directoryId
    )

    Try {
        $wsaHeaders = @{"Accept" = "application/vnd.vmware.horizon.manager.connector.management.directory.domain.list+json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/connectormanagement/directoryconfigs/$directoryId/domains"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
        $response.items
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSADirectoryDomain

Function Add-WSALdapDirectory {
    <#
		.SYNOPSIS
    	Create an LDAP directory

    	.DESCRIPTION
    	The Add-WSALdapDirectory cmdlets creates a new LDAP Active Directory connection in Workspace ONE Access

    	.EXAMPLE
    	Add-WSALdapDirectory -domainName sfo.rainpole.io -baseDn "ou=VVD,dc=sfo,dc=rainpole,dc=io" -bindDn "cn=svc-wsa-ad,ou=VVD,dc=sfo,dc=rainpole,dc=io"
        This example creates a new LDAP Active Directory connection in Workspace ONE Access
  	#>
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainName,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$baseDn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$bindDn,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$certificate
    )

    Try {
        $wsaHeaders = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.ad.over.ldap+json" }
        $wsaHeaders.Add("Accept", "application/vnd.vmware.horizon.manager.connector.management.directory.ad.over.ldap+json")
        $wsaHeaders.Add("Authorization", "$sessionToken")
        if ($PsBoundParameters.ContainsKey("certificate")){
            #read certificate file contents as certdata
            $certdata = (Get-Content ($certificate)) -join "\n"
            $body = '{
                "useSRV":true,
                "directoryType":"ACTIVE_DIRECTORY_LDAP",
                "directorySearchAttribute":"sAMAccountName",
                "directoryConfigId":null,
                "useGlobalCatalog":false,
                "syncConfigurationEnabled":false,
                "useStartTls":true,
                "userAttributeMappings":[],
                "name":"' + $domainName + '",
                "baseDN":"' + $baseDn + '",
                "bindDN":"' + $bindDn + '",
                "sslCertificate":"' + $certdata + '"
            }'
        }else{
            $body = '{
                "useSRV":true,
                "directoryType":"ACTIVE_DIRECTORY_LDAP",
                "directorySearchAttribute":"sAMAccountName",
                "directoryConfigId":null,
                "useGlobalCatalog":false,
                "syncConfigurationEnabled":false,
                "useStartTls":false,
                "userAttributeMappings":[],
                "name":"' + $domainName + '",
                "baseDN":"' + $baseDn + '",
                "bindDN":"' + $bindDn + '"
            }'
        }
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/connectormanagement/directoryconfigs"
        $response = Invoke-RestMethod $uri -Method 'POST' -Headers $wsaHeaders -Body $body
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Add-WSALdapDirectory

Function Set-WSABindPassword {
    <#
		.SYNOPSIS
    	Create an LDAP directory

    	.DESCRIPTION
    	The Set-WSABindPassword cmdlets creates a new LDAP Active Directory connection in Workspace ONE Access

    	.EXAMPLE
    	Set-WSABindPassword -directoryId a1c985d5-0eeb-4a66-bc51-11eda9321aac -connectorId 59ee9717-a09e-45b6-9e5f-8d92a55a1825 -password VMw@re1!
        This example creates a new LDAP Active Directory connection in Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$directoryId,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$connectorId,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass
    )

    Try {
        $wsaHeaders = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.details+json" }
        $wsaHeaders.Add("Accept", "application/vnd.vmware.horizon.manager.connector.management.connector+json")
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $body = '{"directoryId":"' + $directoryId + '","directoryBindPassword":"' + $pass + '","usedForAuthentication":true}'
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/connectormanagement/connectorinstances/$connectorId/associatedirectory"
        $response = Invoke-RestMethod $uri -Method 'POST' -Headers $wsaHeaders -Body $body
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-WSABindPassword

Function Set-WSASyncSetting {
    <#
		.SYNOPSIS
    	Set directory sync schedule

    	.DESCRIPTION
    	The Set-WSASyncSetting cmdlets configures the directory sync schedule in Workspace ONE Access

    	.EXAMPLE
    	Set-WSASyncSetting -directoryId a1c985d5-0eeb-4a66-bc51-11eda9321aac
        This example configures the directory sync schedule in Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$directoryId
    )

    Try {
        $wsaHeaders = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.syncschedule+json" }
        $wsaHeaders.Add("Accept", "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.syncschedule+json")
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $body = '{"frequency":"fifteenMinutes"}'
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/connectormanagement/directoryconfigs/$directoryId/syncprofile"
        Invoke-RestMethod $uri -Method 'PUT' -Headers $wsaHeaders -Body $body
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-WSASyncSetting

Function Start-WSADirectorySync {
    <#
		.SYNOPSIS
    	Start an directory sync

    	.DESCRIPTION
    	The Start-WSADirectorySync cmdlets triggers a directory sync in Workspace ONE Access

    	.EXAMPLE
    	Start-WSADirectorySync -directoryId a1c985d5-0eeb-4a66-bc51-11eda9321aac
        This example starts a directory sync in Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$directoryId
    )

    Try {
        $wsaHeaders = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.sync+json" }
        $wsaHeaders.Add("Accept", "application/vnd.vmware.horizon.v1.0+json")
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $body = '{"ignoreSafeguards":true}'
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/connectormanagement/directoryconfigs/$directoryId/syncprofile/sync"
        Invoke-RestMethod $uri -Method 'POST' -Headers $wsaHeaders -Body $body
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Start-WSADirectorySync

Function Set-WSADirectoryUser {
    <#
		.SYNOPSIS
    	Add users to directory

    	.DESCRIPTION
    	The Set-WSADirectoryUser cmdlets configures the user/ou that should be sycncronised for Workspace ONE Access

    	.EXAMPLE
    	Set-WSADirectoryUser -directoryId a1c985d5-0eeb-4a66-bc51-11eda9321aac -json (Get-Content -Raw .\adUsers.json)
        This example configures the user/ou that should be sycncronised for Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$directoryId,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$json
    )

    Try {
        $wsaHeaders = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.users+json" }
        $wsaHeaders.Add("Accept", "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.users+json")
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/connectormanagement/directoryconfigs/$directoryId/syncprofile"
        Invoke-RestMethod $uri -Method 'PUT' -Headers $wsaHeaders -Body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-WSADirectoryUser

Function Set-WSADirectoryGroup {
    <#
		.SYNOPSIS
    	Add groups to directory

    	.DESCRIPTION
    	The Set-WSADirectoryGroup cmdlets configures the groups/ou that should be sycncronised for Workspace ONE Access

    	.EXAMPLE
    	Set-WSADirectoryUser -directoryId a1c985d5-0eeb-4a66-bc51-11eda9321aac -json (Get-Content -Raw .\adGroups.json)
        This example configures the groups/ou that should be sycncronised for Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$directoryId,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$json
    )

    Try {
        $wsaHeaders = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.groups+json" }
        $wsaHeaders.Add("Accept", "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.groups+json")
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/connectormanagement/directoryconfigs/$directoryId/syncprofile"
        $response = Invoke-RestMethod $uri -Method 'PUT' -Headers $wsaHeaders -Body $json
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-WSADirectoryGroup

Function Get-WSASmtpConfiguration {
    <#
		.SYNOPSIS
    	Get SMTP configuration

    	.DESCRIPTION
    	The Get-WSASmtpConfiguration cmdlets retrieves the SMTP configurtion of Workspace ONE Access

    	.EXAMPLE
    	Get-WSASmtpConfiguration
        This example gets the current SMTP configuration of Workspace ONE Access
  	#>

    Try {
        $wsaHeaders = @{"Accept" = "application/json, text/plain, */*" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/system/config/smtp"
        $response = Invoke-RestMethod $uri -Headers $wsaHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSASmtpConfiguration

Function Set-WSASmtpConfiguration {
    <#
		.SYNOPSIS
    	Set SMTP configuration

    	.DESCRIPTION
    	The Set-WSASmtpConfiguration cmdlets configures the SMTP configurtion of Workspace ONE Access

    	.EXAMPLE
    	Set-WSASmtpConfiguration
        This example sets the SMTP configuration of Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$port,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass
    )

    Try {
        $wsaHeaders = @{"Accept" = "application/json, text/plain, */*" }
        $wsaHeaders.Add("Content-Type", "application/vnd.vmware.horizon.manager.system.config.smtp+json")
        $wsaHeaders.Add("Authorization", "$sessionToken")
        if (-not $PsBoundParameters.ContainsKey("pass")) {
            $body = '{ "host": "' + $fqdn + '", "port": ' + $port + ', "user": "' + $user + '", "password": "' + $pass + '"}'
        }
        else {
            $body = '{ "host": "' + $fqdn + '", "port": ' + $port + ', "user": "' + $user + '" }'
        }
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/system/config/smtp"
        $response = Invoke-RestMethod $uri -Method 'PUT' -Headers $wsaHeaders -Body $body
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-WSASmtpConfiguration

Function Set-WSARoleMember {
    <#
		.SYNOPSIS
    	Set WSA Role Member

    	.DESCRIPTION
    	The Set-WSARoleMember cmdlets updates the Role with the given group

    	.EXAMPLE
    	Set-WSARoleMember -id 55048dee-fe1b-404a-936d-3e0b86a7209e -groupId fe515568-fdcd-43c7-9971-e834d7246203
        This example updates the Role with the given GroupId in Workspace ONE Access
  	#>

	Param (
	    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$id,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$groupId
    )

	Try {
		$wsaHeaders = @{"Content-Type" = "application/json" }
		$wsaHeaders.Add("Authorization", "$sessionToken")
		if ($PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/scim/Roles/$id"

			   $json = @"
						{
				  "schemas": [
					"urn:scim:schemas:core:1.0"
				  ],
				  "members": [
					{
					  "value": "$groupId",
					  "type": "Group"
					}
				  ]
				}
"@
			$response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -body $json -headers $wsaHeaders
            $response
		}
	}
    Catch {
        Write-Error $_.Exception.Message
    }
}

Function Get-WSARole {
    <#
		.SYNOPSIS
    	Get roles

    	.DESCRIPTION
    	The Get-WSARole cmdlets retrieves the roles in Workspace ONE Access

    	.EXAMPLE
    	Get-WSARole
        This example retrieves the roles in Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id
    )

    Try {
        $wsaHeaders = @{"Content-Type" = "application/json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        if ($PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/scim/Roles/$id"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
            $response
        }
        else {
            $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/scim/Roles"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
            $response.Resources
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSARole

Function Get-WSAGroup {
    <#
		.SYNOPSIS
    	Get groups

    	.DESCRIPTION
    	The Get-WSAGroup cmdlets retrieves the groups in Workspace ONE Access

    	.EXAMPLE
    	Get-WSAGroup
        This example retrieves the groups in Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id
    )

    Try {
        $wsaHeaders = @{"Content-Type" = "application/json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        if ($PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/scim/Groups/$id"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
            $response
        }
        else {
            $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/scim/Groups"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
            $response.Resources
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSAGroup

Function Get-WSAUser {
    <#
		.SYNOPSIS
    	Get users

    	.DESCRIPTION
    	The Get-WSAUser cmdlets retrieves the users in Workspace ONE Access

    	.EXAMPLE
    	Get-WSAUser
        This example retrieves the users in Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id
    )

    Try {
        $wsaHeaders = @{"Content-Type" = "application/json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        if ($PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/scim/Users/$id"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
            $response
        }
        else {
            $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/scim/Users"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
            $response.Resources
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSAUser

Function Get-WSARuleSet {
    <#
		.SYNOPSIS
    	Get rulesets

    	.DESCRIPTION
    	The Get-WSARuleSet cmdlets retrieves the rulesets in Workspace ONE Access

    	.EXAMPLE
    	Get-WSARuleSet
        This example retrieves the rulesets in Workspace ONE Access
  	#>

    Try {
        $wsaHeaders = @{"Accept-Type" = "application/json, text/plain, */*" }
        $wsaHeaders.Add("Content-Type", "application/vnd.vmware.vidm.accesscontrol.ruleset.list+json")
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $uri = "https://$workSpaceOne/acs/rulesets"
        $response = Invoke-RestMethod $uri -Headers $wsaHeaders
        $response.items
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSARuleSet

Function Get-WSAOAuthToken {
    <#
		.SYNOPSIS
    	Get AOuth Token

    	.DESCRIPTION
    	The Get-WSAOAuthToken cmdlets gets an OAuth token from Workspace ONE Access

    	.EXAMPLE
    	Get-WSAOAuthToken
        This example retrieves the am OAuth oken from Workspace ONE Access
  	#>

    Try {
        $wsaHeaders = @{"Content-Type" = "application/x-www-form-urlencoded; charset=UTF-8" }
        $wsaHeaders.Add("Accept", "application/json, text/javascript, */*; q=0.01")
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $uri = "https://$workSpaceOne/SAAS/admin/settings/OAuthClient/generateRandomOAuthSecret"
        $response = Invoke-RestMethod $uri -Method 'POST' -Headers $wsaHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSAOAuthToken

Function Get-WSAClient {
    <#
		.SYNOPSIS
    	Get clients

    	.DESCRIPTION
    	The Get-WSAClient cmdlets gets a list of clients in Workspace ONE Access

    	.EXAMPLE
    	Get-WSAClient
        This example retrieves all clients in Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$clientId
    )

    Try {
        $wsaHeaders = @{"Content-Type" = "application/vnd.vmware.horizon.manager.oauth2client+json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        if ($PsBoundParameters.ContainsKey("clientId")) {
            $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/oauth2clients/$clientId"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
            $response
        }
        else {
            $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/oauth2clients"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
            $response.items
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSAClient

Function Add-WSAClient {
    <#
		.SYNOPSIS
    	Add a client

    	.DESCRIPTION
    	The Add-WSAClient cmdlets add a client in Workspace ONE Access

    	.EXAMPLE
    	Add-WSAClient -json .\SampleJson\nsxClient.json
        This example retrieves all clients in Workspace ONE Access
  	#>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$clientId,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$sharedSecret
    )

    Try {
        $wsaHeaders = @{"Content-Type" = "application/vnd.vmware.horizon.manager.oauth2client+json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $body = '{
            "clientId": "' + $clientId + '",
            "secret": "' + $sharedSecret + '",
            "scope": "admin",
            "authGrantTypes": "refresh_token client_credentials",
            "redirectUri": "",
            "tokenType": "Bearer",
            "tokenLength": 32,
            "accessTokenTTL": 8,
            "refreshTokenTTL": 1440,
            "refreshTokenIdleTTL": 4,
            "rememberAs": "' + $clientId + '",
            "displayUserGrant": false,
            "internalSystemClient": false,
            "inheritanceAllowed": true
        }'
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/oauth2clients"
        Invoke-RestMethod $uri -Method 'POST' -Headers $wsaHeaders -body $body
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Add-WSAClient

Function Add-WSARoleAssociation {
    <#
       .SYNOPSIS
       Add the AD group to the WSA role

       .DESCRIPTION
       Add the AD group to the given WSA role.

       .EXAMPLE
       Add-WSARoleAssociation -roleId "1d0b09a1-8744-4f85-8c4f-ac104e586010" -groupId "1e942dc6-94ba-43ef-97ce-9ba34fee1609"
   #>

   Param (
       [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$roleId,
       [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$groupId
   )

   Try {
       $wsaHeaders = @{"Content-Type" = "application/vnd.vmware.vidm.accesscontrol.ruleset.associations.bulk.request+json" }
       $wsaHeaders.Add("Authorization", "$sessionToken")
       $uri = "https://$workSpaceOne/acs/associations/rulesets/$roleId"
       $body = '{
                   "operations": [
                               {
                               "users": [],
                               "groups": [
                                   "'+$groupId+'"
                               ],
                               "associationMethodTO": "POST"
                               },
                               {
                               "users": [],
                               "groups": [],
                               "associationMethodTO": "DELETE"
                               }
                   ]
               }'

       $response = Invoke-RestMethod $uri -Method 'POST' -Headers $wsaHeaders -body $body
       $response
   }
   Catch {
       Write-Error $_.Exception.Message
   }
}
Export-ModuleMember -Function Add-WSARoleAssociation

Function Get-WSARoleId {
   <#
       .SYNOPSIS
       Get role id for role name

       .DESCRIPTION
       Get the role id corresponding to the given role name

       .EXAMPLE
       Get-WSARoleId -role "Super Admin"
       This retrieves the id for the Super Admin role
   #>

   Param (
       [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$role
   )

   Try {
       $wsaHeaders = @{"Content-Type" = "application/json" }
       $wsaHeaders.Add("Authorization", "$sessionToken")
       $uri = "https://$workSpaceOne/acs/rulesets"
       $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
       $roledetails = $response.items | Where-Object {$_.name -eq $role}
       $roleId=$roledetails._links.self.href.split('/')[3]
       $roleId
   }
   Catch {
       Write-Error $_.Exception.Message
   }
}
Export-ModuleMember -Function Get-WSARoleId

Function Get-WSAActiveDirectoryGroupDetail {
   <#
       .SYNOPSIS
       Get details of the given Active Directory group

       .DESCRIPTION
       Get details from Workspace ONE Access of the given Active Directory group

       .EXAMPLE
       Get-WSAActiveDirectoryGroupDetail -group "gg-wsa-admins"
   #>

   Param (
       [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$group
   )

   Try {
       $wsaHeaders = @{"Content-Type" = "application/json" }
       $wsaHeaders.Add("Authorization", "$sessionToken")
       $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/scim/Groups/.search?locale=en"
       $body = '{
                   "attributes": "id,displayName",
                   "filter": "(displayName co \"' + $group + '\")"
                }'
       $response = Invoke-RestMethod $uri -Method 'POST' -Headers $wsaHeaders -body $body
       $response
   }
   Catch {
       Write-Error $_.Exception.Message
   }
}
Export-ModuleMember -Function Get-WSAActiveDirectoryGroupDetail

Function Get-WSARoleAssociation {
   <#
       .SYNOPSIS
       Get associations for the given Role Id

       .DESCRIPTION
       Get details of associations for the given Role Id. This has details of the groups associated with a role.

       .EXAMPLE
       Get-WSARoleAssociation -roleId "1d0b09a1-8744-4f85-8c4f-ac104e586010"
   #>

   Param (
       [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$roleId
   )

   Try {
       $wsaHeaders = @{"Content-Type" = "application/json" }
       $wsaHeaders.Add("Authorization", "$sessionToken")
       $uri = "https://$workSpaceOne/acs/associations/rulesets/$roleId"
       $response = Invoke-RestMethod $uri -Method 'GET' -Headers $wsaHeaders
       $response
   }
   Catch {
       Write-Error $_.Exception.Message
   }
}
Export-ModuleMember -Function Get-WSARoleAssociation

Function Get-WSAPasswordLockout {
    <#
        .SYNOPSIS
        Get password lockout policy

        .DESCRIPTION
        Get details of the password lockout policy for Workspace ONE Access

        .EXAMPLE
        Get-WSAPasswordLockout
    #>

    Try {
        $wsaHeaders = @{"Accept" = "application/vnd.vmware.horizon.manager.password.lockout+json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/passwordlockoutconfig"
        $response = Invoke-RestMethod $uri -Headers $wsaHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSAPasswordLockout

Function Set-WSAPasswordLockout {
    <#
        .SYNOPSIS
        Set password lockout policy

        .DESCRIPTION
        Set details of the password lockout policy for Workspace ONE Access

        .EXAMPLE
        Set-WSAPasswordLockout
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$numAttempts,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$attemptInterval,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$unlockInterval
    )

    Try {
        $wsaHeaders = @{"Accept" = "application/vnd.vmware.horizon.manager.password.lockout+json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $wsaHeaders.Add("Content-Type", "application/vnd.vmware.horizon.manager.password.lockout+json")
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/passwordlockoutconfig"
        $body = '{"numAttempts":'+$numAttempts+',"attemptInterval":'+$attemptInterval+',"unlockInterval":'+$unlockInterval+'}'
        $response = Invoke-RestMethod $uri -Method 'PUT' -Headers $wsaHeaders -Body $body
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-WSAPasswordLockout

 Function Get-WSAPasswordPolicy {
    <#
        .SYNOPSIS
        Get password policy

        .DESCRIPTION
        Get details of the password policy for Workspace ONE Access

        .EXAMPLE
        Get-WSAPasswordPolicy
    #>

    Try {
        $wsaHeaders = @{"Accept" = "application/vnd.vmware.horizon.manager.tenants.tenant.passwordpolicy+json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/tenants/tenant/passwordpolicy"
        $response = Invoke-RestMethod $uri -Headers $wsaHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSAPasswordPolicy

Function Set-WSAPasswordPolicy {
    <#
        .SYNOPSIS
        Set password lockout policy

        .DESCRIPTION
        Set details of the password lockout policy for Workspace ONE Access

        .EXAMPLE
        Set-WSAPasswordPolicy -minLen 6 -minLower 0 -minUpper 0 -minDigit 0 -minSpecial 0 -history 0 -maxConsecutiveIdenticalCharacters 3 -maxPreviousPasswordCharactersReused 2 -tempPasswordTtlInHrs 167 -passwordTtlInDays 81 -notificationThresholdInDays 16 -notificationIntervalInDays 11
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$minLen,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$minLower,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$minUpper,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$minDigit,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$minSpecial,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$history,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$maxConsecutiveIdenticalCharacters,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$maxPreviousPasswordCharactersReused,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$tempPasswordTtlInHrs,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$passwordTtlInDays,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$notificationThresholdInDays,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$notificationIntervalInDays

    )

    Try {
        $wsaHeaders = @{"Accept" = "application/vnd.vmware.horizon.manager.tenants.tenant.passwordpolicy+json" }
        $wsaHeaders.Add("Authorization", "$sessionToken")
        $wsaHeaders.Add("Content-Type", "application/vnd.vmware.horizon.manager.tenants.tenant.passwordpolicy+json")
        $uri = "https://$workSpaceOne/SAAS/jersey/manager/api/tenants/tenant/passwordpolicy"
		$passwordTtlInHours = [int]$passwordTtlInDays * 24
		$notificationThresholdInMilliSec = [int]$notificationThresholdInDays * 24 * 3600 * 1000
		$notificationIntervalInMilliSec = [int]$notificationIntervalInDays * 24 * 3600 * 1000
		$body = '{
            "minLen":'+$minLen+',
            "minLower":'+$minLower+',
            "minUpper":'+$minUpper+',
            "minDigit":'+$minDigit+',
            "minSpecial":'+$minSpecial+',
            "history":'+$history+',
            "maxConsecutiveIdenticalCharacters":'+$maxConsecutiveIdenticalCharacters+',
            "maxPreviousPasswordCharactersReused":'+$maxPreviousPasswordCharactersReused+',
            "tempPasswordTtl":'+$tempPasswordTtlInHrs+',
            "passwordTtlInHours":'+$passwordTtlInHours+',
            "notificationThreshold":'+$notificationThresholdInMilliSec+',
            "notificationInterval":'+$notificationIntervalInMilliSec+'
        }'
		Write-OutPut $body
        $response = Invoke-RestMethod $uri -Method 'PUT' -Headers $wsaHeaders -Body $body
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-WSAPasswordPolicy

############  End Workspace ONE Access Functions  ############
##############################################################


##############################################################
############  Begin NSX-T Data Center Functions  #############

Function Request-NsxToken {
    <#
        .SYNOPSIS
        Connects to the specified NSX Manager

        .DESCRIPTION
        The Request-NsxToken cmdlet connects to the specified NSX Manager with the supplied credentials

        .EXAMPLE
        Request-NsxToken -fqdn sfo-w01-nsx01.sfo.rainpole.io -username admin -password VMware1!VMw@re1!
        This example shows how to connect to NSX Manager

        .EXAMPLE
        Get-NsxtServerDetail -fqdn sfo-vcf01.sfo.rainpole.io -username admin@local -password VMw@re1!VMw@re1! -domain sfo-w01 | Request-NsxToken
        This example shows how to connect to NSX Manager using pipeline input from Get-NsxtServerDetail
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()][String]$fqdn,
        [Parameter (Mandatory = $false)] [String]$username,
        [Parameter (Mandatory = $false)] [String]$password,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psobject]$inputObject
    )

    if ($inputObject) {
        $username = $inputObject.adminUser
        $password = $inputObject.adminPass
        $fqdn = $inputObject.fqdn
        $sddcManager = (Get-VCFManager).fqdn
    }
    else {
        if (!$PsBoundParameters.ContainsKey("username") -or (!$PsBoundParameters.ContainsKey("password"))) {
            # Request Credentials
            $creds = Get-Credential
            $username = $creds.UserName.ToString()
            $password = $creds.GetNetworkCredential().password
        }
        if (!$PsBoundParameters.ContainsKey("fqdn")) {
            $fqdn = Read-Host "NSX Manager FQDN not found, please enter a value e.g. sfo-m01-nsx01.sfo.rainpole.io"
        }
    }

    # Validate credentials by executing an API call
    $Global:nsxtHeaders = createBasicAuthHeader $username $password
    $Global:nsxtmanager = $fqdn
    $uri = "https://$nsxtmanager/api/v1/logical-ports"

    Try {
        # Checking against the NSX Managers API
        # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $nsxtHeaders -SkipCertificateCheck
        }
        else {
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $nsxtHeaders
        }
        if ($response) {
            if ($inputObject) {
                Write-Output "Successfully Requested New API Token for NSX Manager $nsxtmanager via SDDC Manager $sddcManager"
            }
            else {
                Write-Output "Successfully Requested New API Token for NSX Manager $nsxtmanager"
            }
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Request-NsxToken

Function Get-NsxtComputeManager {
    <#
    .SYNOPSIS
    Retrieves a list of compute managers from NSX Manager

    .DESCRIPTION
    The Get-NsxtComputeManager cmdlet gets compute managers from NSX Manager

    .EXAMPLE
    Get-NsxtComputeManager
    This example gets all compute managers

    .EXAMPLE
    Get-NsxtComputeManager -vCenterServer "sfo-m01-vc01.sfo.rainpole.io"
    This example gets the compute manager named "sfo-m01-vc01.sfo.rainpole.io"
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$vCenterServer
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("vCenterServer")) {
            $uri = "https://$nsxtManager/api/v1/fabric/compute-managers"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results
        }
        elseif ($PsBoundParameters.ContainsKey("vCenterServer")) {
            $uri = "https://$nsxtManager/api/v1/fabric/compute-managers"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $responseChecked = $response.results | Where-Object { $_.server -eq $vCenterServer }

            if (!$responseChecked) {
                Write-Output "Compute Manager $vCenterServer was not found."
            }
            elseif ($responseChecked) {
                $responseChecked
            }
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtComputeManager

Function Set-NsxtComputeManager {
    <#
    .SYNOPSIS
    Configure a set of parameters on a compute manager

    .DESCRIPTION
    The Set-NsxtComputeManager cmdlet configures a set of parameters on a compute manager

    .EXAMPLE
    Get-NsxtComputeManager -vCenterServer sfo-w01-vc01.sfo.rainpole.io | Set-NsxtComputeManager -EnableTrust:$true
    This example enables trust (sets OIDC provider to true) for Compute Manager sfo-w01-vc01.sfo.rainpole.io
    In this release, it is required to use pipeline input from Get-NsxtComputeManager.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Bool]$EnableTrust,
        [Parameter (ValueFromPipeline, Mandatory = $true)] [psObject]$inputObject
    )

    # Validating pipeline input resource_type
    if ($inputObject.resource_type -ne "ComputeManager") {
        Write-Error "Invalid pipeline passthrough."
        break
    }
    elseif ($inputObject.resource_type -eq "ComputeManager") {
        $computeManagerId = $inputObject.id
        $computeManagerRevision = $inputObject._revision
        $computeManagerFqdn = $inputObject.server
        $computeManagerOriginType = $inputObject.origin_type
        $computeManagerSetAsOidcProvider = $inputObject.set_as_oidc_provider
        $computeManagerCredentialType = $inputObject.credential.credential_type
        $computeManagerCredentialThumbprint = $inputObject.credential.thumbprint
    }

    if ($EnableTrust -eq $computeManagerSetAsOidcProvider) {
        Write-Error -Message "Compute Manager trust is already set to $EnableTrust."
        break
    }

    $json = @"
{
"_revision" : $computeManagerRevision,
"server" : "$computeManagerFqdn",
"origin_type" : "$computeManagerOriginType",
"set_as_oidc_provider" : "$EnableTrust",
"credential" :
{
    "credential_type" : "$computeManagerCredentialType",
    "thumbprint" : "$computeManagerCredentialThumbprint"
}
}
"@

    Try {
        $uri = "https://$nsxtManager/api/v1/fabric/compute-managers/$computeManagerId"
        $response = Invoke-RestMethod -Method PUT -URI $uri -ContentType application/json -body $json -headers $nsxtHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-NsxtComputeManager

Function Get-NsxtVidm {
    <#
        .SYNOPSIS
        Get Identity Manager Configuration

        .DESCRIPTION
        The Get-NsxtVidm cmdlet gets the Identity Manager Configuration

        .EXAMPLE
        Get-NsxtVidm
        This example gets the Identity Manager Configuration
    #>

    Try {
        $uri = "https://$nsxtManager/api/v1/node/aaa/providers/vidm"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $nsxtHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtVidm

Function Set-NsxtVidm {
    <#
        .SYNOPSIS
        Set Identity Manager Configuration

        .DESCRIPTION
        The Set-NsxtVidm cmdlet configures Identity Manager in NSX-T Manager

        .EXAMPLE
        Set-NsxtVidm
        This example configures the Identity Manager in NSX-T Manager
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$wsaHostname,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$thumbprint,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$clientId,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$sharedSecret,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$nsxHostname
    )

    Try {
        $uri = "https://$nsxtManager/api/v1/node/aaa/providers/vidm"
        $body = '{
            "lb_enable": false,
            "vidm_enable": true,
            "host_name": "' + $wsaHostname + '",
            "thumbprint": "' + $thumbprint + '",
            "client_id": "' + $clientId + '",
            "client_secret": "' + $sharedSecret + '",
            "node_host_name": "' + $nsxHostname + '"
        }'
        $response = Invoke-RestMethod $uri -Method 'PUT' -Headers $nsxtHeaders -body $body
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-NsxtVidm

Function Get-NsxtRole {
    <#
        .SYNOPSIS
        Gets NSX-T Manager roles

        .DESCRIPTION
        The Get-NsxtRole cmdlet gets the roles in NSX-T Manager

        .EXAMPLE
        Get-NsxtRole
        This example gets all roles in NSX-T Manager
    #>

    Try {
        $uri = "https://$nsxtManager/api/v1/aaa/roles"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $nsxtHeaders
        $response.results
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtRole

Function Set-NsxtRole {
    <#
        .SYNOPSIS
        Adds a role to a user/group

        .DESCRIPTION
        The Set-NsxtRole cmdlet assigns users/groups to roles

        .EXAMPLE
        Set-NsxtRole -principle "gg-nsx-enterprise-admins@lax.rainpole.io"
        This example assigned the provided group the Enterprise Admin role
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$principal,
        [Parameter (Mandatory = $true)] [ValidateSet("remote_group", "remote_user")] [String]$type,
        [Parameter (Mandatory = $true)] [ValidateSet("lb_admin", "security_engineer", "vpn_admin", "network_op", "netx_partner_admin", "gi_partner_admin", "security_op", "network_engineer", "lb_auditor", "auditor", "enterprise_admin")] [String]$role,
        [Parameter (Mandatory = $true)] [ValidateSet("LDAP", "VIDM", "OIDC")] [String]$identitySource
    )

    Try {
        $uri = "https://$nsxtManager/api/v1/aaa/role-bindings"
        $body = '{
            "name": "' + $principal + '",
            "type": "' + $type + '",
            "identity_source_type": "' + $identitySource + '",
            "roles": [
                    {
                        "role": "' + $role + '"
                    }
                ]
            }'
        $response = Invoke-RestMethod $uri -Method 'POST' -Headers $nsxtHeaders -Body $body
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-NsxtRole

Function Remove-NsxtRole {
    <#
        .SYNOPSIS
        Delete a user/group role assignment

        .DESCRIPTION
        The Remove-NsxtRole cmdlet removes a user/group role in NSX-T Manager

        .EXAMPLE
        Remove-NsxtRole -id
        This example removes the role for the user/group based on the id
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$id
    )

    Try {
        $uri = "https://$nsxtManager/api/v1/aaa/role-bindings/$id"
        $response = Invoke-RestMethod $uri -Method 'DELETE' -Headers $nsxtHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Remove-NsxtRole

Function Get-NsxtUser {
    <#
        .SYNOPSIS
        Gets all users and groups

        .DESCRIPTION
        The Get-NsxtUser cmdlet gets all users and groups in NSX-T Manager

        .EXAMPLE
        Get-NsxtUser
        This example gets all users and grops in NSX-T Manager
    #>

    Try {
        $uri = "https://$nsxtManager/api/v1/aaa/role-bindings"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $nsxtHeaders
        $response.results
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtUser

Function Get-NsxtVidmUser {
    <#
        .SYNOPSIS
        Gets vIDM users

        .DESCRIPTION
        The Get-NsxtVidmUser cmdlet gets all vIDM users from NSX-T Manager

        .EXAMPLE
        Get-NsxtVidmUser -searchString svc
        This example gets all vIDM users starting with 'svc' from NSX-T Manager
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateLength(3, 255)] [String]$searchString
    )

    Try {
        $uri = "https://$nsxtManager/api/v1/aaa/vidm/users?search_string=$searchString"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $nsxtHeaders
        $response.results
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtVidmUser

Function Get-NsxtVidmGroup {
    <#
        .SYNOPSIS
        Gets vIDM groups

        .DESCRIPTION
        The Get-NsxtVidmGroup cmdlet gets all vIDM groups from  NSX-T Manager

        .EXAMPLE
        Get-NsxtVidmGroup -searchString gg-
        This example gets all vIDM groups starting with gg- from NSX-T Manager
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateLength(3, 255)] [String]$searchString
    )

    Try {
        $uri = "https://$nsxtManager/api/v1/aaa/vidm/groups?search_string=$searchString"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $nsxtHeaders
        $response.results
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtVidmGroup

Function Get-NsxtEdgeCluster {
    <#
        .SYNOPSIS
        Retrieves NSX-T Edge Cluster(s)

        .DESCRIPTION
        The Get-NsxtEdgeCluster cmdlet retrieves NSX-T Edge Cluster(s)

        .EXAMPLE
        Get-NsxtEdgeCluster
        This example returns any NSX-T Edge Clusters

        .EXAMPLE
        Get-NsxtEdgeCluster -Name "sfo-w01-ec01"
        This example returns any NSX-T Edge Clusters
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Name
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("Name")) {
            $uri = "https://$nsxtmanager/api/v1/edge-clusters"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results
        }
        elseif ($PsBoundParameters.ContainsKey("Name")) {
            $uri = "https://$nsxtmanager/api/v1/edge-clusters"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $responseChecked = $response.results | Where-Object { $_.display_name -eq $Name }

            if (!$responseChecked) {
                Write-Output "NSX-T Edge Cluster $Name was not found."
            }
            elseif ($responseChecked) {
                $responseChecked
            }
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtEdgeCluster

Function Get-NsxtTransportZone {
    <#
        .SYNOPSIS
        Get a list of Transport Zones

        .DESCRIPTION
        The Get-NsxtTransportZone cmdlet retrieves a list of Transport Zones

        .EXAMPLE
        Get-NsxtTransportZone
        This example gets all Transport Zones

        .EXAMPLE
        Get-NsxtTransportZone -Name overlay-tz-sfo-w01-nsx01.sfo.rainpole.io
        This example gets the Transport Zone with the name "overlay-tz-sfo-w01-nsx01.sfo.rainpole.io"
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Name
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("Name")) {
            $uri = "https://$nsxtManager/api/v1/transport-zones"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results | Sort-Object display_name
        }
        elseif ($PsBoundParameters.ContainsKey("Name")) {
            $uri = "https://$nsxtManager/api/v1/transport-zones"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $responseChecked = $response.results | Where-Object { $_.display_name -eq $Name }

            if (!$responseChecked) {
                Write-Output "NSX Transport Zone $Name was not found"
            }
            elseif ($responseChecked) {
                $responseChecked
            }
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtTransportZone

Function New-NsxtSegment {
    <#
        .SYNOPSIS
        Create a new NSX-T Segment

        .DESCRIPTION
        The New-NsxtSegment cmdlet creates NSX-T Segments

        .EXAMPLE
        New-NsxtSegment -Name "sfo-w01-xreg-seg01" -GatewayType "Tier1" -ConnectedGateway "sfo-w01-ec01-t1-gw01" -Cidr "192.168.31.1/24" -TransportZone "overlay-tz-sfo-w01-nsx01.sfo.rainpole.io"
        This example creates an NSX-T Overlay Segment with the name "sfo-w01-xreg-seg01", connected to Tier-1 gateway "sfo-w01-ec01-t1-gw01", Transport Zone "overlay-tz-sfo-w01-nsx01.sfo.rainpole.io", and CIDR address of "192.168.31.1/24"
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$Name,
        [Parameter (Mandatory = $false)] [String]$ConnectedGateway,
        [Parameter (Mandatory = $false)] [String]$Cidr,
        [Parameter (Mandatory = $true)] [String]$TransportZone,
        [Parameter (Mandatory = $false)] [ValidateSet("Tier0", "Tier1")] [String]$GatewayType,
        [Parameter (Mandatory = $true)] [ValidateSet("Overlay", "VLAN")] [String]$SegmentType,
        [Parameter (Mandatory = $false)] [String]$VlanId
    )

    if ($GatewayType -eq "Tier0") {
        $connectivityPath = (Get-NsxtTier0Gateway -Name $ConnectedGateway).path
    }
    elseif ($GatewayType -eq "Tier1") {
        $connectivityPath = (Get-NsxtTier1Gateway -Name $ConnectedGateway).path
    }
    elseif (!$GatewayType -and $VlanId) {
        Write-Output "Valid VLAN segment configuration"
    }
    else {
        Write-Error "Gateway type not defined"
    }

    $transportZoneId = (Get-NsxtTransportZone -Name $TransportZone).id

    if ($SegmentType -match "overlay") {

        $json = @"
{
"display_name" : "$Name",
"subnets" : [{ "gateway_address" : "$Cidr" }],
"connectivity_path" : "$connectivityPath",
"transport_zone_path" : "/infra/sites/default/enforcement-points/default/transport-zones/$transportZoneId"
}
"@

    }
    elseif ($SegmentType -match "vlan") {

        $json = @"
{
"display_name" : "$Name",
"vlan_ids" : [ "$VlanId" ],
"transport_zone_path" : "/infra/sites/default/enforcement-points/default/transport-zones/$transportZoneId"
}
"@

    }
    else {
        Write-Error "SegmentType $SegmentType is invalid."
    }

    Try {
        $uri = "https://$nsxtManager/policy/api/v1/infra/segments/$Name"
        $response = Invoke-RestMethod -Method PUT -URI $uri -ContentType application/json -Body $json -headers $nsxtHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtSegment

Function Get-NsxtSegment {
    <#
        .SYNOPSIS
        Get a list of Segments

        .DESCRIPTION
        The Get-NsxtSegment cmdlet retrieves a list of Segments

        .EXAMPLE
        Get-NsxtSegment
        This example gets all Segments

        .EXAMPLE
        Get-NsxtSegment -name sfo-w01-kub-seg01
        This example gets the segment with the name sfo-w01-kub-seg01
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$name
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("name")) {
            $uri = "https://$nsxtManager/policy/api/v1/infra/segments/"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results | Sort-Object display_name
        }
        elseif ($PsBoundParameters.ContainsKey("name")) {
            $uri = "https://$nsxtManager/policy/api/v1/infra/segments/"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results | Where-Object { $_.display_name -eq $name }
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtSegment

Function Remove-NsxtSegment {
    <#
        .SYNOPSIS
        Removes a named Segment

        .DESCRIPTION
        The Remove-NsxtSegment cmdlet removes a named segment.

        .EXAMPLE
        Remove-NsxtSegment -name sfo-w01-kub-seg01
        This example removes the segment with the name sfo-w01-kub-seg01
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Name
    )

    Try {
        $preCheckSegment = Get-NsxtSegment -Name $name -ErrorAction SilentlyContinue
    }
    Catch {
        Write-Error $_.Exception.Message
    }

    if ($preCheckSegment -eq "NSX segment $Name was not found") {
        Write-Error $preCheckSegment
        Break
    }

    Try {
        $uri = "https://$nsxtManager/policy/api/v1/infra/segments/$Name"
        $response = Invoke-RestMethod -Method DELETE -URI $uri -ContentType application/json -headers $nsxtHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }

    # Validation
    Try {
        $checkSegment = Get-NsxtSegment -Name $Name -ErrorAction SilentlyContinue
    }
    Catch {
        Write-Error $_.Exception.Message
    }

    if ($checkSegment -eq "NSX segment $Name was not found") {
        Write-Output "NSX-T Segment $Name has been successfully deleted."
    }
    else {
        Write-Error -Message "NSX-T Segment $Name was not deleted. Please check the logs."
    }
}
Export-ModuleMember -Function Remove-NsxtSegment

Function Get-NsxtTier0Gateway {
    <#
        .SYNOPSIS
        Get a list of Tier 0 Gateways

        .DESCRIPTION
        The Get-NsxtTier0 cmdlet retrieves a list of Tier 0 Gateways

        .EXAMPLE
        Get-NsxtTier0Gateway
        This example returns all Tier 0 Gateways

        .EXAMPLE
        Get-NsxtTier0Gateway -name sfo-w01-ec01-t0-gw01
        This example returns the Tier 0 Gateway named sfo-w01-ec01-t0-gw01

        .EXAMPLE
        Get-NsxtTier0Gateway -id 84a6c7a5-9fe8-4446-8684-814663399584
        This example returns the Tier 0 Gateway based on its id
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$name,
        [Parameter (Mandatory = $false)] [String]$id
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("name") -and !$PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$nsxtmanager/policy/api/v1/infra/tier-0s"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results
        }
        elseif ($PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$nsxtmanager/policy/api/v1/infra/tier-0s/$id"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response
        }
        elseif ($PsBoundParameters.ContainsKey("name")) {
            $uri = "https://$nsxtmanager/policy/api/v1/infra/tier-0s"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results | Where-Object { $_.display_name -eq $name }
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtTier0Gateway

Function Get-NsxtTier1Gateway {
    <#
        .SYNOPSIS
        Get a list of Tier 1 Gateways

        .DESCRIPTION
        The Get-NsxtTier1Gateway cmdlet retrieves a list of Tier 1 Gateways

        .EXAMPLE
        Get-NsxtTier1Gateway
        This example returns all Tier 1 Gateways

        .EXAMPLE
        Get-NsxtTier1Gateway -name sfo-w01-ec01-t1-gw01
        This example returns the Tier 1 Gateway named sfo-w01-ec01-t1-gw01

        .EXAMPLE
        Get-NsxtTier1Gateway -id 84a6c7a5-9fe8-4446-8684-814663399584
        This example returns the Tier 1 Gateway based on its id
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$name,
        [Parameter (Mandatory = $false)] [String]$id
    )

    Try {
        if ( -not $PsBoundParameters.ContainsKey("name")) {
            $uri = "https://$nsxtmanager/policy/api/v1/infra/tier-1s"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results
        }
        elseif ($PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$nsxtmanager/policy/api/v1/infra/tier-1s/$id"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response
        }
        elseif ($PsBoundParameters.ContainsKey("name")) {
            $uri = "https://$nsxtmanager/policy/api/v1/infra/tier-1s"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results | Where-Object { $_.display_name -eq $name }
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtTier1Gateway

Function Get-NsxtPrefixList {
    <#
        .SYNOPSIS
        Get Tier-0 Gateway IP Prefix Lists

        .DESCRIPTION
        The Get-NsxtTier0PrefixList cmdlet retrieves the IP Prefix Lists assigned to a Tier-0 Gateway

        .EXAMPLE
        Get-NsxtPrefixList -tier0Gateway sfo-w01-ec01-t0-gw01
        This example returns all IP Prefix Lists

        .EXAMPLE
        Get-NsxtPrefixList -name sfo-w01-cl01-prefix-list -tier0Gateway sfo-w01-ec01-t0-gw01
        This example returns the IP Prefix List based on the prefix name provided

        .EXAMPLE
        Get-NsxtTier0Gateway -name sfo-w01-ec01-t0-gw01 | Get-NsxtPrefixList -name sfo-w01-cl01-prefix-list
        This example returns the IP Prefix List based on the prefix name provided
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$tier0Gateway,
        [Parameter (Mandatory = $false)] [String]$name,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    # Validating pipeline input resource_type
    if ($inputObject -and $inputObject.resource_type -eq "Tier0") {
        $tier0Gateway = $inputObject.display_name
        $uriPath = $inputObject.path
    }
    elseif ($inputObject -and $inputObject.resource_type -ne "Tier0") {
        Write-Error "Invalid pipeline passthrough. Exiting."
        Break
    }
    elseif (!$inputObject -and $Tier0Gateway) {
        $uriPath = (Get-NsxtTier0Gateway -Name $Tier0Gateway).path
    }
    else {
        if (!$tier0Gateway) {
            $tier0Gateway = Read-Host -Prompt "Tier-0 Gateway not defined. Type in the name of your Tier-0 Gateway, then press Enter"
        }
    }

    Try {
        if (!$name) {
            $uri = "https://$nsxtmanager/policy/api/v1"+$uriPath+"/prefix-lists"
            $response = Invoke-RestMethod -Method GET -URI $uri -headers $nsxtHeaders -ErrorAction SilentlyContinue
            $response.results
        }
        elseif ($name) {
            $uri = "https://$nsxtmanager/policy/api/v1"+$uriPath+"/prefix-lists"
            $response = Invoke-RestMethod -Method GET -URI $uri -headers $nsxtHeaders -ErrorAction SilentlyContinue
            $response.results | Where-Object { $_.display_name -eq $name }
        }
    }
    Catch {
        if ($_.Exception -match "400" -or $_.Exception -match "Bad Request") {
            Write-Output $uri
            Write-Error "The NSX Tier-0 Gateway was not properly defined"

        }
    }
}
Export-ModuleMember -Function Get-NsxtPrefixList

Function New-NsxtPrefixList {
    <#
        .SYNOPSIS
        Creates a Tier-0 Gateway IP Prefix List

        .DESCRIPTION
        The New-NsxtPrefixList cmdlet creates a Prefix List on a specified Tier-0 Gateway

        .EXAMPLE
        New-NsxtPrefixList -Name sfo-w01-cl01-prefix-list -Tier0Gateway sfo-w01-ec01-t0-gw01
        This example creates a new IP Prefix List on a Tier 0 Gateway
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Name,
        [Parameter (Mandatory = $false)] [String]$Tier0Gateway,
        [Parameter (Mandatory = $false)] [String]$SubnetCIDR,
        [Parameter (Mandatory = $false)] [String]$GE,
        [Parameter (Mandatory = $false)] [String]$LE,
        [Parameter (Mandatory = $false)] [ValidateSet("PERMIT", "DENY")] [String]$Action,
        [Parameter (Mandatory = $false)] [String]$Json,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    # Validating pipeline input resource_type
    if ($inputObject -and $inputObject.resource_type -eq "Tier0") {
        $uriPath = $inputObject.path
        $Tier0Gateway = $inputObject.display_name
    }
    elseif ($inputObject -and $inputObject.resource_type -ne "Tier0") {
        Write-Error "Invalid pipeline passthrough. Exiting."
        Break
    }
    elseif (!$inputObject) {
        if (!$Tier0Gateway) {
            $Tier0Gateway = Read-Host -Prompt "Tier-0 Gateway not defined. Type in the name of your Tier-0 Gateway, then press Enter"
            $uriPath = (Get-NsxtTier0Gateway -Name $Tier0Gateway).path
        }
    }

    if (!$json) {
        if (!$GE -or !$LE) {
            $Json = @"
{
    "display_name" : "$Name",
    "prefixes" :
    [
        {
        "network" : "$SubnetCIDR",
        "action" : "$Action"
        }
    ]
}
"@
        }
        elseif ($GE -and $LE) {
            $Json = @"
{
    "display_name" : "$Name",
    "prefixes" :
    [
        {
        "network" : "$SubnetCIDR",
        "action" : "$Action",
        "ge" : "$GE",
        "le" : "$LE"
        }
    ]
}
"@
        }
        else {
            Write-Error "Invalid subnet configuration."
        }
    }

    Try {
        $global:uri = "https://$nsxtmanager/policy/api/v1"+$uriPath+"/prefix-lists/$Name"
        $global:response = Invoke-RestMethod -Method PUT -URI $uri -ContentType application/json -body $json -headers $nsxtHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtPrefixList

Function Remove-NsxtPrefixList {
    <#
        .SYNOPSIS
        Remove an IP Prefix List from a Tier-0 Gateway

        .DESCRIPTION
        The Remove-NsxtPrefixList cmdlet removes a IP Prefix List from a specified Tier-0 Gateway

        .EXAMPLE
        Remove-NsxtPrefixList -Name sfo-w01-cl01-prefix-list -Tier0Gateway sfo-w01-ec01-t0-gw01
        This example removes a Prefix List on a Tier 0 Gateway
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Name,
        [Parameter (Mandatory = $false)] [String]$Tier0Gateway,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    # Validating pipeline input resource_type
    if ($inputObject -and $inputObject.resource_type -eq "Tier0") {
        $uriPath = $inputObject.path
    }
    elseif ($inputObject -and $inputObject.resource_type -ne "Tier0") {
        Write-Error "Invalid pipeline passthrough. Exiting."
        Break
    } elseif (!$inputObject) {
        if (!$Tier0Gateway) {
            $Tier0Gateway = Read-Host -Prompt "Tier-0 Gateway not defined. Type in the name of your Tier-0 Gateway, then press Enter"
        }
        $uriPath = (Get-NsxtTier0Gateway -Name $Tier0Gateway).path
    }

    Try {
        $preCheckPrefixList = Get-NsxtPrefixList -Name $Name -Tier0Gateway $Tier0Gateway -ErrorAction SilentlyContinue
    }
    Catch {
        Write-Error $_.Exception.Message
    }

    if ($preCheckPrefixList -eq "NSX IP Prefix List $Name was not found") {
        Write-Error $preCheckPrefixList
        Break
    }

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1"+$uriPath+"/prefix-lists/$Name"
        $response = Invoke-RestMethod -Method DELETE -URI $uri -headers $nsxtHeaders -ContentType application/json
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }

    # Validation
    Try {
        $checkPrefixList = Get-NsxtPrefixList -Name $Name -Tier0Gateway $Tier0Gateway -ErrorAction SilentlyContinue
    }
    Catch {
        Write-Error $_.Exception.Message
    }

    if ($checkPrefixList -eq "NSX IP Prefix List $Name was not found") {
        Write-Output "NSX-T PrefixList $Name has been successfully deleted."
    }
    else {
        Write-Error -Message "NSX-T PrefixList $Name was not deleted. Please check the logs."
    }
}
Export-ModuleMember -Function Remove-NsxtPrefixList

Function Add-NsxtPrefix {
    <#
        .SYNOPSIS
        Add a single entry to an existing NSX IP Prefix List

        .DESCRIPTION
        The Add-NsxtPrefix cmdlet adds a single entry to an existing NSX IP Prefix List

        .EXAMPLE
        Get-NsxtPrefixList -name sfo-w01-cl01-prefix-list | Add-NsxtPrefix -subnetCIDR 192.168.21.0/24 -LE 32 -GE 28 -action PERMIT
        This example adds an IP Prefix entry on an existing IP Prefix List
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$prefixListName,
        [Parameter (Mandatory = $false)] [String]$tier0Gateway,
        [Parameter (Mandatory = $false)] [String]$subnetCIDR,
        [Parameter (Mandatory = $false)] [String]$GE,
        [Parameter (Mandatory = $false)] [String]$LE,
        [Parameter (Mandatory = $false)] [String]$action,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    if (!$inputObject -and $tier0Gateway -and $prefixListName) {
        $uriPath = (Get-NsxtTier0Gateway -Name $tier0Gateway).path
        $existingPrefixes = (Get-NsxtPrefixList -Name $prefixListName -Tier0Gateway $tier0Gateway).prefixes
    }

    if ($inputObject -and $inputObject.resource_type -eq "PrefixList") {
        $uriPath = $inputObject.parent_path
        $Tier0GatewayId = $inputObject.parent_path.Split('/')[3]
        $PrefixListName = $inputObject.display_name
        $existingPrefixes = $inputObject.prefixes

        $getTier0Gateway = Get-NsxtTier0Gateway -name $tier0GatewayId -ErrorAction SilentlyContinue

        if ($getTier0Gateway -eq "NSX Tier-0 Gateway $tier0GatewayId was not found") {
            $tier0Gateway = (Get-NsxtTier0Gateway -Id $tier0GatewayId).display_name
        }
        else {
            $Tier0Gateway = $Tier0GatewayId
        }

    }
    elseif ($inputObject -and $inputObject.resource_type -ne "PrefixList") {
        Write-Error "Invalid pipeline passthrough"
        Break
    }

    $prefixes = @()

    $prefixes += $existingPrefixes

    if (!$GE -or !$LE) {
        $newPrefix = @{
            network = $subnetCIDR
            action  = $action
        }
    }
    elseif ($GE -and $LE) {
        $newPrefix = @{
            network = $subnetCIDR
            action  = $action
            ge      = $GE
            le      = $LE
        }
    }
    else {
        Write-Error "Invalid subnet configuration"
    }

    $prefixes += $newPrefix
    $prefixesJson = $prefixes | ConvertTo-Json

    $json = @"
    {
        "display_name": "$PrefixListName",
        "prefixes": $prefixesJson
    }
"@

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1"+$uriPath+"/prefix-lists/$PrefixListName"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -body $json -headers $nsxtHeaders
        $response

        if (!$response) {
            $output = Get-NsxtPrefixList -Name $PrefixListName -Tier0Gateway $Tier0Gateway
            $output
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Add-NsxtPrefix

Function Add-NsxtPrefixList {
    <#
        .SYNOPSIS
        Add an IP Prefix List to a Route Map

        .DESCRIPTION
        The Add-NsxtPrefixList cmdlet adds an IP Prefix List to a Route Map

        .EXAMPLE
        Get-NsxtPrefixList -Name sfo-w01-cl01-prefix-list | Add-NsxtPrefixList -RouteMap sfo-w01-ec01-route-map -Action PERMIT
        This example adds an IP Prefix List to a specific Route Map
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Name,
        [Parameter (Mandatory = $false)] [String]$Tier0Gateway,
        [Parameter (Mandatory = $false)] [String]$RouteMap,
        [Parameter (Mandatory = $false)] [String]$Action,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    if ($inputObject) {
        $Tier0GatewayId = $inputObject.parent_path.Split('/')[3]
        $Tier0Gateway = (Get-NsxtTier0Gateway -Id $Tier0GatewayId).display_name

        if ($inputObject.resource_type -eq "Tier0RouteMap") {
            $RouteMap = $inputObject.display_name
            $existingEntries = $inputObject.entries
            $uriPath = $inputObject.parent_path
        }
        elseif ($inputObject.resource_type -eq "PrefixList" -and $RouteMap) {
            $routeMapInput = Get-NsxtTier0Gateway -Name $Tier0Gateway | Get-NsxtRouteMap -Name $RouteMap
            $existingEntries = $routeMapInput.entries
            $uriPath = $routeMapInput.parent_path
        }
        else {
            Write-Error "Invalid pipeline passthrough. Exiting."
            Break
        }
    }

    $prefixListPath = (Get-NsxtTier0Gateway -Name $Tier0Gateway | Get-NsxtPrefixList -Name $Name).path
    $prefixListPathArray = @()
    $prefixListPathArray += $prefixListPath

    $existingEntriesPrefixListMatches = $existingEntries.prefix_list_matches
    $existingPrefixListPathArray = @()
    $existingPrefixListPathArray += $existingEntriesPrefixListMatches

    $existingEntriesAction = $existingEntries.action


    $existingEntry = @{
        prefix_list_matches = $existingPrefixListPathArray
        action              = $existingEntriesAction
    }

    $newEntry = @{
        prefix_list_matches = $prefixListPathArray
        action              = $Action
    }

    $entries = @()
    $entries += $existingEntry
    $entries += $newEntry

    $entriesJson = $entries | ConvertTo-Json

    $json = @"
    {
        "entries": $entriesJson
    }
"@

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/"+$uriPath+"/route-maps/$RouteMap"
        $response = Invoke-RestMethod -Method PUT -URI $uri -ContentType application/json -body $json -headers $nsxtHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Add-NsxtPrefixList

Function Get-NsxtRouteMap {
    <#
        .SYNOPSIS
        Get Tier-0 Gateway Route Maps

        .DESCRIPTION
        The Get-NsxtRouteMap cmdlet retrieves the Route Maps assigned to a specified Tier-0 Gateway

        .EXAMPLE
        Get-NsxtRouteMap -tier0Gateway sfo-w01-ec01-t0-gw01
        This example gets all Route Maps on the Tier-0 Gateway

        .EXAMPLE
        Get-NsxtRouteMap -tier0Gateway sfo-w01-ec01-t0-gw01 -name sfo-w01-ec01-t0-gw01-routemap
        This example gets a specific route map by name from the Tier-0 Gateway
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$tier0Gateway,
        [Parameter (Mandatory = $false)] [String]$name,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    # Validating pipeline input resource_type
    if ($inputObject -and $inputObject.resource_type -eq "Tier0") {
        $tier0Gateway = $inputObject.display_name
        $uriPath = $inputObject.path
    }
    elseif ($inputObject -and $inputObject.resource_type -ne "Tier0") {
        Write-Error "Invalid pipeline passthrough. Exiting."
        Break
    }
    elseif (!$inputObject) {
        if (!$tier0Gateway) {
            Write-Output "Tier 0 Gateway: $Tier0Gateway"
            $Tier0Gateway = Read-Host -Prompt "Tier-0 Gateway not defined. Type in the name of your Tier-0 Gateway, then press Enter"
        }
        $uriPath = (Get-NsxtTier0Gateway -Name $tier0Gateway).path
    }

    Try {
        if (!$PsBoundParameters.ContainsKey("Name")) {
            $uri = "https://$nsxtmanager/policy/api/v1"+$uriPath+"/route-maps"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results
        }
        elseif ($PsBoundParameters.ContainsKey("Name")) {
            $uri = "https://$nsxtmanager/policy/api/v1"+$uriPath+"/route-maps"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results | Where-Object { $_.display_name -eq $Name }
        }
    }
    Catch {
        if ($_.Exception -match "400" -or $_.Exception -match "Bad Request") {
            Write-Error "The NSX Tier-0 Gateway was not properly defined."
        }
    }
}
Export-ModuleMember -Function Get-NsxtRouteMap

Function New-NsxtRouteMap {
    <#
        .SYNOPSIS
        Creates a Route Map on a specified Tier-0 Gateway

        .DESCRIPTION
        The New-NsxtRouteMap cmdlet creates a Route Map on a specified Tier-0 Gateway

        .EXAMPLE
        New-NsxtRouteMap -Name sfo-w01-cl01-route-map -Tier0Gateway sfo-w01-ec01-t0-gw01 -PrefixList sfo-w01-ec01-prefix-list
        This example creates a new Route Map on a Tier-0 Gateway

        .EXAMPLE
        Net-NsxtTier0Gateway sfo-w01-ec01-t0-gw01 | Get-NsxtPrefixList -Name sfo-w01-ec01-prefix-list | New-NsxtRouteMap -Name sfo-w01-cl01-route-map
        This example creates a new Route Map on a Tier-0 Gateway
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Name,
        [Parameter (Mandatory = $false)] [String]$Tier0Gateway,
        [Parameter (Mandatory = $false)] [String]$PrefixList,
        [Parameter (Mandatory = $false)] [String]$Action,
        [Parameter (Mandatory = $false)] [String]$Json,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    if ($inputObject) {
        if ($inputObject.resource_type -eq "Tier0") {
            $Tier0Gateway = $inputObject.display_name
            $Tier0GatewayId = $inputObject.id
            $uriPath = $inputObject.path
        }
        elseif ($inputObject.resource_type -eq "PrefixList") {
            $Tier0GatewayId = $inputObject.parent_path.Split('/')[3]
            $PrefixListPath = $inputObject.path
            $Tier0Gateway = (Get-NsxtTier0Gateway -Id $Tier0GatewayId).display_name
            $uriPath = $inputObject.parent_path
        }
        else {
            Write-Error "Invalid pipeline passthrough. Exiting."
            Break
        }
    } elseif (!$inputObject){
        $uriPath = (Get-NsxtTier0Gateway -Name $Tier0Gateway).path
    }

    if (!$PrefixListPath) {
        $PrefixListPath = $uriPath+"/prefix-lists/"+$PrefixList
    }

    $json = @"
{
    "display_name" : "$Name",
    "entries" :
    [
        {
        "action" : "$Action",
        "prefix_list_matches" : [ "$prefixListPath" ]
        }
    ]
}
"@

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1"+$uriPath+"/route-maps/$Name"
        $response = Invoke-RestMethod -Method PUT -URI $uri -ContentType application/json -body $json -headers $nsxtHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtRouteMap

Function Remove-NsxtRouteMap {
    <#
        .SYNOPSIS
        Remove a Route Map from a specified Tier-0 Gateway

        .DESCRIPTION
        The Remove-NsxtRouteMap cmdlet removes a Route Map attached to a specified Tier-0 Gateway

        .EXAMPLE
        Remove-NsxtRouteMap -name sfo-w01-ec01-t0-gw01-routemap -tier0Gateway sfo-w01-ec01-t0-gw01
        This example removes the Route Map sfo-w01-ec01-t0-gw01-routemap from Tier-0 Gateway sfo-w01-ec01-t0-gw01
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$name,
        [Parameter (Mandatory = $false)] [String]$tier0Gateway,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    if ($inputObject) {
        if ($inputObject.resource_type -eq "Tier0RouteMap") {
            $Name = $inputObject.display_name
            $Tier0GatewayId = $inputObject.parent_path.Split('/')[3]
            $Tier0Gateway = (Get-NsxtTier0Gateway -Id $Tier0GatewayId).display_name
            $uriPath = $inputObject.parent_path
        }
        elseif ($inputObject.resource_type -eq "Tier0" -and $Name -and !$Tier0Gateway) {
            $Tier0GatewayId = $inputObject.id
            $Tier0Gateway = $inputObject.display_name
            $uriPath = $inputObject.path
        }
        else {
            Write-output $inputObject.resource_type
            Write-Error "Invalid pipeline passthrough. Exiting."
            Break
        }
    }
    elseif (!$inputObject) {
        if (!$tier0Gateway) {
            $tier0Gateway = Read-Host -Prompt "Tier-0 Gateway not defined. Type in the name of your Tier-0 Gateway, then press Enter"
        }
        $uriPath = (Get-NsxtTier0Gateway -Name $Tier0Gateway).path
    }

    Try {
        $preCheckRouteMap = Get-NsxtRouteMap -name $Name -tier0Gateway $Tier0Gateway -ErrorAction SilentlyContinue
    }
    Catch {
        Write-Error $_.Exception.Message
    }

    if ($preCheckRouteMap -eq "NSX-T RouteMap $Name was not found.") {
        Write-Error $preCheckRouteMap
        Break
    }

    # Check if the route map is applied to the route redistribution configuration
    Try {
        $getRouteRedistribution = Get-NsxtRouteRedistributionPolicy -tier0Gateway $tier0Gateway
        if ($getRouteRedistribution.route_redistribution_config.redistribution_rules.route_map_path -eq $preCheckRouteMap.path) {
            $getRouteRedistribution | Set-NsxtRouteRedistributionPolicy -tier0Gateway $tier0Gateway -RemoveRouteMap:$True | Out-Null
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1"+$uriPath+"/route-maps/$name"
        $response = Invoke-RestMethod -Method DELETE -URI $uri -headers $nsxtHeaders -ContentType application/json
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
        Break
    }

    # Validation
    Try {
        $checkRouteMap = Get-NsxtRouteMap -Name $Name -Tier0Gateway $Tier0Gateway -ErrorAction SilentlyContinue
    }
    Catch {
        Write-Error $_.Exception.Message
    }

    if ($checkRouteMap -eq "NSX-T RouteMap $Name was not found.") {
        Write-Output "NSX-T RouteMap $Name has been successfully deleted."
    }
    else {
        Write-Error -Message "NSX-T RouteMap $Name was not deleted. Please check the logs."
    }
}
Export-ModuleMember -Function Remove-NsxtRouteMap

Function Get-NsxtRouteRedistributionPolicy {
    <#
        .SYNOPSIS
        Get the route redistribution policy from a Tier-0 Gateway

        .DESCRIPTION
        The Get-NsxtRouteRedistributionPolicy cmdlet get the route redistribution policy from a Tier-0 Gateway

        .EXAMPLE
        Get-NsxtRouteRedistributionPolicy -tier0Gateway sfo-w01-ec01-t0-gw01
        This example returns the route redistribution policy for Tier-0 Gateway sfo-w01-ec01-t0-gw01
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$tier0Gateway,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    if ($inputObject -and $inputObject.resource_type -eq "Tier0") {
        $Tier0Gateway = $inputObject.display_name
        $uriPath = $inputObject.path
    }
    elseif ($inputObject -and $inputObject.resource_type -ne "Tier0") {
        Write-Error "Invalid pipeline passthrough. Exiting."
        Break
    }
    elseif (!$inputObject) {
        if (!$Tier0Gateway) {
            $Tier0Gateway = Read-Host -Prompt "Tier-0 Gateway not defined. Type in the name of your Tier-0 Gateway, then press Enter"
        }
        $uriPath = (Get-NsxtTier0Gateway -Name $Tier0Gateway).path
    }

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1"+$uriPath+"/locale-services/default"
        $response = Invoke-RestMethod -Method GET -URI $uri -headers $nsxtHeaders -ContentType application/json
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }

}
Export-ModuleMember Get-NsxtRouteRedistributionPolicy

Function Set-NsxtRouteRedistributionPolicy {
    <#
        .SYNOPSIS
        Set the route redistriution policy for a Tier 0 Gateway

        .DESCRIPTION
        The Set-NsxtRouteRedistributionPolicy cmdlet sets the route redistriution policy for a Tier 0 Gateway

        .EXAMPLE
        Get-NsxtRouteRedistributionPolicy -tier0Gateway "sfo-w01-ec01-t0-gw01" | Set-NsxtRouteRedistributionPolicy -RouteMap "sfo-w01-ec01-t0-gw01-routemap"
        This example sets the RouteMap "sfo-w01-ec01-t0-gw01-routemap" on the route redistribution policy for Tier-0 Gateway "sfo-w01-t0-ec01-t0-gw01"
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$tier0Gateway,
        [Parameter (Mandatory = $false)] [String]$routeMap,
        [Parameter (Mandatory = $false)] [Bool]$removeRouteMap,
        [Parameter (ValueFromPipeline, Mandatory = $true)] [psObject]$inputObject
    )

    if ($inputObject -and $inputObject.resource_type -eq "LocaleServices") {
        $Tier0GatewayId = $inputObject.parent_path.Split('/')[3]
        $Tier0Gateway = (Get-NsxtTier0Gateway -Id $Tier0GatewayId).display_name
        $edgeClusterPath = $inputObject.edge_cluster_path
        $bgpEnabled = $inputObject.route_redistribution_config.bgp_enabled
        $routeRedistributionName = $inputObject.route_redistribution_config.redistribution_rules.name
        $routeRedistributionTypes = $inputObject.route_redistribution_config.redistribution_rules.route_redistribution_types
        $uriPath = $inputObject.parent_path
    }
    elseif ($inputObject -and $inputObject.resource_type -ne "LocaleServices") {
        Write-Error "Invalid pipeline passthrough. Exiting."
        Break
    }

    if (!$inputObject) {
        if (!$Tier0Gateway) {
            $Tier0Gateway = Read-Host -Prompt "Tier-0 Gateway not defined. Type in the name of your Tier-0 Gateway, then press Enter"
        }

        $getRedistributionPolicy = Get-NsxtTier0Gateway -Name $Tier0Gateway

        $edgeClusterPath = $getRedistributionPolicy.edge_cluster_path
        $bgpEnabled = $getRedistributionPolicy.route_redistribution_config.bgp_enabled
        $routeRedistributionName = $getRedistributionPolicy.route_redistribution_config.redistribution_rules.name
        $routeRedistributionTypes = $getRedistributionPolicy.route_redistribution_config.redistribution_rules.route_redistribution_types
        $uriPath = (Get-NsxtTier0Gateway -Name $Tier0Gateway).path
    }

    $routeMapPath = "/infra/tier-0s/$Tier0GatewayId/route-maps/$RouteMap"

    foreach ($routeRedistributionType in $routeRedistributionTypes) {
        $routeRedistributionTypeString += @"
"$routeRedistributionType",
"@
    }

    $routeRedistributionTypeString = $routeRedistributionTypeString.Substring(0, $routeRedistributionTypeString.Length - 1)

    if ($RemoveRouteMap -eq $true) {
        $json = @"
{
    "edge_cluster_path" : "$edgeClusterPath",
    "route_redistribution_config" :
    {
        "bgp_enabled" : "$bgpEnabled",
        "redistribution_rules" :
        [
            {
            "name" : "$routeRedistributionName",
            "route_redistribution_types" : [ $routeRedistributionTypeString ]
            }
        ]
    }
}
"@
    }
    elseif ($RemoveRouteMap -eq $false -or !$RemoveRouteMap) {
        $json = @"
{
    "edge_cluster_path" : "$edgeClusterPath",
    "route_redistribution_config" :
    {
        "bgp_enabled" : "$bgpEnabled",
        "redistribution_rules" :
        [
            {
            "name" : "$routeRedistributionName",
            "route_redistribution_types" : [ $routeRedistributionTypeString ],
            "route_map_path" : "$routeMapPath"
            }
        ]
    }
}
"@
    }

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1"+$uriPath+"/locale-services/default"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -headers $nsxtHeaders -ContentType application/json -body $json
        $response

        if (!$response) {
            $output = Get-NsxtRouteRedistributionPolicy -Tier0Gateway $Tier0Gateway
            $output
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }

}
Export-ModuleMember Set-NsxtRouteRedistributionPolicy

Function Get-NsxtManagerAuthPolicy {
    <#
        .SYNOPSIS
        Get the Authentication Policy for NSX Manager Nodes

        .DESCRIPTION
        The Get-NsxtManagerAuthPolicy cmdlet getss the current authentication policy for NSX Manager Node

        .EXAMPLE
        Get-NsxtManagerAuthPolicy -nsxtManagerNode "sfo-m01-nsx01a.sfo.rainpole.io"
		This example returns the current Authentication policy in NSX manager node sfo-m01-nsx01a.sfo.rainpole.io
    #>

	Param (
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$nsxtManagerNode
	)

	Try {
		$requestingURL = "https://" + $nsxtManagerNode + "/api/v1/node/aaa/auth-policy"
		$response = Invoke-RestMethod -Method GET -URI $requestingURL -ContentType application/json -headers $nsxtHeaders
		$response
	}
	Catch {
		Write-Error $_.Exception.Message
	}
}
Export-ModuleMember Get-NsxtManagerAuthPolicy

Function Set-NsxtManagerAuthPolicy {
    <#
        .SYNOPSIS
        Set the Authentication Policy for NSX Manager Node

        .DESCRIPTION
        The Set-NsxtManagerAuthPolicy cmdlet configures the authentication policy for NSX Manager Node

        .EXAMPLE
        Set-NsxManagerAuthPolicy -nsxtManagerNode "sfo-m01-nsx01a.sfo.rainpole.io" -api_lockout_period 900 -api_reset_period 120 -api_max_attempt 5 -cli_lockout_period 900 -cli_max_attempt 5 -min_passwd_length 15
		This example customized the Authentication policy in NSX manager node sfo-m01-nsx01a.sfo.rainpole.io.
    #>

	Param (
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$nsxtManagerNode,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$api_lockout_period,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$api_reset_period,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$api_max_attempt,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$cli_lockout_period,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$cli_max_attempt,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$min_passwd_length
	)

	$authPolicyBody = @{}
	if ($PsBoundParameters.ContainsKey("api_lockout_period")) {
		$authPolicyBody+= @{api_failed_auth_lockout_period = $api_lockout_period}
	}
	if ($PsBoundParameters.ContainsKey("api_reset_period")) {
		$authPolicyBody += @{api_failed_auth_reset_period = $api_reset_period}
	}
	if ($PsBoundParameters.ContainsKey("api_max_attempt")) {
		$authPolicyBody += @{api_max_auth_failures = $api_max_attempt}
	}
	if ($PsBoundParameters.ContainsKey("cli_lockout_period")) {
		$authPolicyBody += @{cli_failed_auth_lockout_period = $cli_lockout_period}
	}
	if ($PsBoundParameters.ContainsKey("cli_max_attempt")) {
		$authPolicyBody += @{cli_max_auth_failures = $cli_max_attempt}
	}
	if ($PsBoundParameters.ContainsKey("min_passwd_length")) {
		$authPolicyBody += @{minimum_password_length = $min_passwd_length}
	}

	Try {
		$requestingURL = "https://" + $nsxtManagerNode + "/api/v1/node/aaa/auth-policy"
		$response = Invoke-RestMethod -Method PUT -URI $requestingURL -ContentType application/json -headers $nsxtHeaders -Body ($authPolicyBody | ConvertTo-Json)
		$response
	}
	Catch {
		Write-Error $_.Exception.Message
	}
}
Export-ModuleMember Set-NsxtManagerAuthPolicy

Function Get-NsxtEdgeNodeAuthPolicy {
    <#
        .SYNOPSIS
        Get the Authentication Policy for NSX Edge Nodes

        .DESCRIPTION
        The Get-NsxtEdgeNodeAuthPolicy cmdlet getss the authentication policy for NSX Edge Nodes

        .EXAMPLE
        Get-NsxtEdgeNodeAuthPolicy -nsxtManagerNode "sfo-m01-nsx01a.sfo.rainpole.io"
		This example returns the password policy in NSX manager node sfo-m01-nsx01a.sfo.rainpole.io
    #>

	Param (
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$nsxtManager,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$nsxtEdgeNodeID
	)

	Try {
		$requestingURL = "https://" + $nsxtManager + "/api/v1/transport-nodes/" + $nsxtEdgeNodeID + "/node/aaa/auth-policy"
		$response = Invoke-RestMethod -Method GET -URI $requestingURL -ContentType application/json -headers $nsxtHeaders
		$response
	}
	Catch {
		Write-Error $_.Exception.Message
	}
}
Export-ModuleMember Get-NsxtEdgeNodeAuthPolicy

Function Set-NsxtEdgeNodeAuthPolicy {
    <#
        .SYNOPSIS
        Set the Authentication Policy for NSX Manager Nodes

        .DESCRIPTION
        The Set-NsxtManagerAuthPolicy cmdlet getss the authentication policy for NSX Manager Nodes

        .EXAMPLE
        Set-NsxManagerAuthPolicy -nsxtManagerNode "sfo-m01-nsx01a.sfo.rainpole.io" -api_lockout_period 900 -api_reset_period 120 -api_max_attempt 5 -cli_lockout_period 900 -cli_max_attempt 5 -min_passwd_length 15
		This example customized the password policy in NSX manager node sfo-m01-nsx01a.sfo.rainpole.io.
    #>

	Param (
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$nsxtManager,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$nsxtEdgeNodeID,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$cli_lockout_period,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$cli_max_attempt,
		[Parameter (Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [int]$min_passwd_length
	)

	$authPolicyBody = @{}
	if ($PsBoundParameters.ContainsKey("cli_lockout_period")) {
		$authPolicyBody += @{cli_failed_auth_lockout_period = $cli_lockout_period}
	}
	if ($PsBoundParameters.ContainsKey("cli_max_attempt")) {
		$authPolicyBody += @{cli_max_auth_failures = $cli_max_attempt}
	}
	if ($PsBoundParameters.ContainsKey("min_passwd_length")) {
		$authPolicyBody += @{minimum_password_length = $min_passwd_length}
	}

	Try {
		$requestingURL = "https://" + $nsxtManager + "/api/v1/transport-nodes/" + $nsxtEdgeNodeID + "/node/aaa/auth-policy"
		$response = Invoke-RestMethod -Method PUT -URI $requestingURL -ContentType application/json -headers $nsxtHeaders -Body ($authPolicyBody | ConvertTo-Json)
		$response
	}
	Catch {
		Write-Error $_.Exception.Message
	}
}
Export-ModuleMember Set-NsxtEdgeNodeAuthPolicy

Function Get-NsxtSyslogStatus {
    <#
        .SYNOPSIS
        Gets the status of the Syslog Service

        .DESCRIPTION
        The Get-NsxtSyslogStatus cmdlet gets the status of the Syslog Service for NSX-T Data Center components

        .EXAMPLE
        Get-NsxtSyslogStatus -type node
        This example gets the status of the syslog service for NSX Manager node

        .EXAMPLE
        Get-NsxtSyslogStatus -type transport -id f3bd5bf0-23cd-4c6f-8de5-ab065f74d7fe
        This example gets the status of the syslog service for NSX Edge node
    #>

    Param (
        [Parameter (ParameterSetName = 'node', Mandatory = $true)] [ValidateNotNullOrEmpty()] [Switch]$node,
        [Parameter (ParameterSetName = 'transport', Mandatory = $true)] [ValidateNotNullOrEmpty()] [Switch]$transport,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id
    )

    Try {
        if ($PsBoundParameters.ContainsKey("node")) {
            $uri = "https://$nsxtManager/api/v1/node/services/syslog/status"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $nsxtHeaders
            $response
        }
        if ($PsBoundParameters.ContainsKey("transport")) {
            $uri = "https://$nsxtManager/api/v1/transport-nodes/$id/node/services/syslog/status"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $nsxtHeaders
            $response
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtSyslogStatus

Function Get-NsxtSyslogExporter {
    <#
        .SYNOPSIS
        Gets Syslog exporters

        .DESCRIPTION
        The Get-NsxtSyslogExporter cmdlet gets the Syslog exporters configures for NSX-T Data Center components

        .EXAMPLE
        Get-NsxtSyslogExporter -node
        This example gets the configuration of the syslog exporters for NSX Manager node

        .EXAMPLE
        Get-NsxtSyslogExporter -transport -id f3bd5bf0-23cd-4c6f-8de5-ab065f74d7fe
        This example gets the configuration of the syslog exporters for NSX Edge node
    #>

    Param (
        [Parameter (ParameterSetName = 'node', Mandatory = $true)] [ValidateNotNullOrEmpty()] [Switch]$node,
        [Parameter (ParameterSetName = 'transport', Mandatory = $true)] [ValidateNotNullOrEmpty()] [Switch]$transport,
        [Parameter (ParameterSetName = 'transport', Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id
    )

    Try {
        if ($PsBoundParameters.ContainsKey("node")) {
            $uri = "https://$nsxtManager/api/v1/node/services/syslog/exporters"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $nsxtHeaders
            $response.results
        }
        if ($PsBoundParameters.ContainsKey("transport")) {
            $uri = "https://$nsxtManager/api/v1/transport-nodes/$id/node/services/syslog/exporters"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $nsxtHeaders
            $response.results
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtSyslogExporter

Function Set-NsxtSyslogExporter {
    <#
        .SYNOPSIS
        Sets Syslog exporters

        .DESCRIPTION
        The Set-NsxtSyslogExporter cmdlet Sets the Syslog exporters configures for NSX-T Data Center components

        .EXAMPLE
        Set-NsxtSyslogExporter -node -exporterName Syslog1 -logLevel INFO -port 514 -protocol TCP -server sfo-vrli01.sfo.rainpole.io
        This example gets the status of the syslog service for NSX Manager node

        .EXAMPLE
        Set-NsxtSyslogExporter -transport -id f3bd5bf0-23cd-4c6f-8de5-ab065f74d7fe -exporterName Syslog1 -logLevel INFO -port 514 -protocol TCP -server sfo-vrli01.sfo.rainpole.io
        This example gets the status of the syslog service for NSX Edge node
    #>

    Param (
        [Parameter ( ParameterSetName = 'node', Mandatory = $true)] [ValidateNotNullOrEmpty()] [Switch]$node,
        [Parameter ( ParameterSetName = 'transport', Mandatory = $true)] [ValidateNotNullOrEmpty()] [Switch]$transport,
        [Parameter ( ParameterSetName = 'transport', Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id,
        [Parameter ( Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$exporterName,
        [Parameter ( Mandatory = $true)] [ValidateSet("EMERG", "ALERT", "CRIT", "ERR", "WARNING", "NOTICE", "INFO", "DEBUG")]  [String]$logLevel,
        [Parameter ( Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int]$port,
        [Parameter ( Mandatory = $true)] [ValidateSet("TCP", "TLS", "UDP", "LI", "LI-TLS")] [String]$protocol,
        [Parameter ( Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server
    )

      Try {
        $json = '{
            "exporter_name": "' + $exporterName + '",
            "level": "' + $logLevel + '",
            "port": ' + $port + ',
            "protocol": "' + $protocol + '",
            "server": "' + $server + '"
        }'

        if ($PsBoundParameters.ContainsKey("node")) {
            $uri = "https://$nsxtManager/api/v1/node/services/syslog/exporters"
            $response = Invoke-RestMethod $uri -Method 'POST' -Headers $nsxtHeaders -ContentType application/json -body $json
            $response
        }
        if ($PsBoundParameters.ContainsKey("transport")) {
            $uri = "https://$nsxtManager/api/v1/transport-nodes/$id/node/services/syslog/exporters"
            $response = Invoke-RestMethod $uri -Method 'POST' -Headers $nsxtHeaders -ContentType application/json -body $json
            $response
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-NsxtSyslogExporter

Function Remove-NsxtSyslogExporter {
    <#
        .SYNOPSIS
        Delete Syslog exporters

        .DESCRIPTION
        The Remove-NsxtSyslogExporter cmdlet deletes the Syslog exporters for NSX-T Data Center components

        .EXAMPLE
        Remove-NsxtSyslogExporter -node -exporterName Syslog1
        This example deletes the syslog exporters for NSX Manager node

        .EXAMPLE
        Remove-NsxtSyslogExporter -transport -id f3bd5bf0-23cd-4c6f-8de5-ab065f74d7fe -exporterName Syslog1
        This example deletes the syslog exporters for for NSX Edge node
    #>

    Param (
        [Parameter (ParameterSetName = 'node', Mandatory = $true)] [ValidateNotNullOrEmpty()] [Switch]$node,
        [Parameter (ParameterSetName = 'transport', Mandatory = $true)] [ValidateNotNullOrEmpty()] [Switch]$transport,
        [Parameter (ParameterSetName = 'transport', Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id,
        [Parameter ( Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$exporterName
    )

    Try {
        if ($PsBoundParameters.ContainsKey("node")) {
            $uri = "https://$nsxtManager/api/v1/node/services/syslog/exporters/$exporterName"
            $response = Invoke-RestMethod $uri -Method 'DELETE' -Headers $nsxtHeaders
            $response
        }
        if ($PsBoundParameters.ContainsKey("transport")) {
            $uri = "https://$nsxtManager/api/v1/transport-nodes/$id/node/services/syslog/exporters/$exporterName"
            $response = Invoke-RestMethod $uri -Method 'DELETE' -Headers $nsxtHeaders
            $response
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Remove-NsxtSyslogExporter

Function Copy-vRealizeLoadBalancer 
{
    <#
        .SYNOPSIS
        Creates a Load Balancer for vRealize component failover

        .DESCRIPTION
        Creates a new loadbalancer in a secondary VMware Cloud Foundation instance by duplicating the settings of the existing load balancer in the instance where the vRealize components are currently running

        .EXAMPLE
        Copy-vRealizeLoadBalancer -sddcManagerAFQDN sfo-vcf01.sfo.rainpole.io -sddcManagerAUser administrator@vsphere.local -sddcManagerAPassword VMw@re1! -sddcManagerBFQDN lax-vcf01.lax.rainpole.io -sddcManagerBUser administrator@vsphere.local -sddcManagerBPassword VMw@re1! -serviceInterfaceIP 192.168.11.3 -wsaCertName xint-wsa01
        This example copies settings from Load Balancer in SDDC A to a new Load Balancer in SDDC B
    #>
    
    Param (
        [Parameter (Mandatory = $true)] [String]$sddcManagerAFqdn,
        [Parameter (Mandatory = $true)] [String]$sddcManagerAUser,
        [Parameter (Mandatory = $true)] [String]$sddcManagerAPassword,
        [Parameter (Mandatory = $true)] [String]$sddcManagerBFqdn,
        [Parameter (Mandatory = $true)] [String]$sddcManagerBUser,
        [Parameter (Mandatory = $true)] [String]$sddcManagerBPassword,
        [Parameter (Mandatory = $true)] [String]$serviceInterfaceIp,
        [Parameter (Mandatory = $true)] [String]$wsaCertName
    )

    Try {
        # Setup Parameters
        $t1Name = "recovery-t1-gw01"
        $siName = "recovery-t1-gw01-si01"
        $lbName = "recovery-lb01"

        #Retrieve Edge Cluster Details from SDDC Manager B
        Request-VCFToken -fqdn $sddcManagerBFqdn -Username $sddcManagerBUser -Password $sddcManagerBPassword | Out-Null
        $mgmtNsxtClusterID = (Get-VCFWorkloadDomain | Where-Object {$_.type -eq "Management"}).nsxtCluster.id
        $edgeClusterName = (Get-VCFEdgeCluster | Where-Object {$_.nsxtCluster.id -eq $mgmtNsxtClusterID}).Name
        
        #Retrieve Segment, WSA, VRA and vROPS  Details from SDDC Manager A
        Request-VCFToken -fqdn $sddcManagerAFqdn -Username $sddcManagerAUser -Password $sddcManagerAPassword | Out-Null
        $xintSegmentDetails = Get-VCFApplicationVirtualNetwork | Where-Object {$_.regionType -eq "X_REGION"}
        $wsaDetailsObject = Get-WSAServerDetail -fqdn $sddcManagerAFqdn -username $sddcManagerAUser -password $sddcManagerAPassword
        $vraDetailsObject = Get-vRAServerDetail -fqdn $sddcManagerAFqdn -username $sddcManagerAUser -password $sddcManagerAPassword
        $vropsDetailsObject = Get-vROPsServerDetail -fqdn $sddcManagerAFqdn -username $sddcManagerAUser -password $sddcManagerAPassword

        #Add Cert to NSX
        $nsxManager = Get-NsxtServerDetail -fqdn $sddcManagerBFqdn -user $sddcManagerBUser -pass $sddcManagerBPassword -domainType MANAGEMENT
        Request-NsxToken -fqdn $nsxManager.fqdn -username $nsxManager.adminUser -password $nsxManager.adminPass | Out-Null

        #Get xint segment ID from NSX LM on recovery site
        $segmentID = Get-NsxtGlobalSegmentID -segmentName $xintSegmentDetails.name
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
    
    Try {
        if ((!$edgeClusterName) -OR (!$xintSegmentDetails) -OR (!$wsaDetailsObject) -OR ((!$vraDetailsObject) -AND (!$vropsDetailsObject))) {
            Write-Output "Requirements for Copying Load Balancer not Met".
            if (!$wsaDetailsObject) {Write-Output "Clustered Workspace ONE Access was not discovered in the source SDDC Manager instance"}
            if ((!$vraDetailsObject) -AND (!$vropsDetailsObject)) {Write-Output "Neither vRealize Automation nor vRealize Operations Manager was discovered in the source SDDC Manager instance"}
            if (!$xintSegmentDetails) {Write-Output "Cross-Region Segment was discovered in the target SDDC Manager instance"}
            if (!$edgeClusterName) {Write-Output "Management Edge Cluster was not discovered in the target SDDC Manager instance"}
        }
        else {    
            #Create a Load Balancer Spec
            if (!$vraDetailsObject) {
                $lbCustomObject = New-vRealizeLoadBalancerSpec -xintSegmentDetails $xintSegmentDetails -serviceInterfaceIp $serviceInterfaceIp -wsaDetailsObject $wsaDetailsObject -vropsDetailsObject $vropsDetailsObject -wsaCertName $wsaCertName -t1Name $t1Name -lbName $lbName -siName $siName -segmentID $segmentID
            }
            elseif (!$vropsDetailsObject) {
                $lbCustomObject = New-vRealizeLoadBalancerSpec -xintSegmentDetails $xintSegmentDetails -serviceInterfaceIp $serviceInterfaceIp -wsaDetailsObject $wsaDetailsObject -vraDetailsObject $vraDetailsObject -wsaCertName $wsaCertName -t1Name $t1Name -lbName $lbName -siName $siName -segmentID $segmentID
            }
            else {
                $lbCustomObject = New-vRealizeLoadBalancerSpec -xintSegmentDetails $xintSegmentDetails -serviceInterfaceIp $serviceInterfaceIp -wsaDetailsObject $wsaDetailsObject -vraDetailsObject $vraDetailsObject -vropsDetailsObject $vropsDetailsObject -wsaCertName $wsaCertName -t1Name $t1Name -lbName $lbName -siName $siName -segmentID $segmentID
            }

            $wsaCertPresent = Add-CertToNsxCertificateStore -certName $wsaCertName
        
            if ($wsaCertPresent -eq $true) {
                $ConfigJson = $lbCustomObject.t1_spec.gw | ConvertTo-Json
                New-NsxtTier1 -tier1Gateway $t1Name -json $ConfigJson
                $edgeClusterID = (Get-NsxtEdgeCluster -name $edgeClusterName).id
                $ConfigJson = '{"edge_cluster_path": "/infra/sites/default/enforcement-points/default/edge-clusters/' + $edgeClusterID + '"}'
                Set-NsxtTier1 -tier1Gateway $t1name -json $ConfigJson
                $ConfigJson = '{
                    "segment_path": "'+ $lbCustomObject.t1_spec.service_interface.segment_path + '",
                    "subnets": [
                    {
                        "ip_addresses": [ "'+ $lbCustomObject.t1_spec.service_interface.subnets.ip_addresses + '" ],
                        "prefix_len": "'+ $lbCustomObject.t1_spec.service_interface.subnets.prefix_len + '"
                    }
                    ]
                    }'
                New-NsxtTier1ServiceInterface -tier1Gateway $t1name -interfaceId $lbCustomObject.t1_spec.service_interface.id -json $ConfigJson
                $ConfigJson = '{
                    "network": "'+ $lbCustomObject.t1_spec.static_routes.network + '",
                    "next_hops": [
                        {
                            "ip_address": "'+ $lbCustomObject.t1_spec.static_routes.next_hops.ip_address + '",
                            "admin_distance": '+ $lbCustomObject.t1_spec.static_routes.next_hops.admin_distance + ',
                            "scope": [
                                "'+ $lbCustomObject.t1_spec.static_routes.next_hops.scope +'"                    
                            ]
                        }
                    ],
                    "display_name": "'+ $lbCustomObject.t1_spec.static_routes.display_name + '"
                    }'
                New-NsxtTier1StaticRoute -tier1Gateway $t1name -segment $xintSegmentDetails.name -json $ConfigJson
                $ConfigJson = $lbCustomObject.lb_spec.lb_service | ConvertTo-Json
                New-NsxtLoadBalancer -lbName $lbName -json $ConfigJson
                Foreach ($monitor in $lbCustomObject.lb_spec.service_monitors) {
                    Try {
                        $ConfigJson = $monitor | ConvertTo-Json -Depth 10
                        New-NsxtLBServiceMonitor -monitorName $monitor.display_name -json $ConfigJson
                    }
                    Catch {
                        Debug-ExceptionWriter -object $_
                    }
                }
                Foreach ($profile in $lbCustomObject.lb_spec.app_profiles) {
                    Try {
                        $ConfigJson = $profile | ConvertTo-Json
                        New-NsxtLBAppProfile -appProfileName $profile.display_name -json $ConfigJson
                    }
                    Catch {
                        Debug-ExceptionWriter -object $_
                    }
                }
                Foreach ($profile in $lbCustomObject.lb_spec.persistence_profiles) {
                    Try {
                        $ConfigJson = $profile | ConvertTo-Json
                        New-NsxtLBPersistenceAppProfile -appProfileName $profile.display_name -json $ConfigJson
                    }
                    Catch {
                        Debug-ExceptionWriter -object $_
                    }
                }
                Foreach ($pool in $lbCustomObject.lb_spec.pools) {
                    Try {
                        $ConfigJson = $pool | ConvertTo-Json
                        New-NsxtLBPool -poolName $pool.display_name -json $ConfigJson
                    }
                    Catch {
                        Debug-ExceptionWriter -object $_
                    }
                }
                Foreach ($virtualServer in $lbCustomObject.lb_spec.virtual_Servers) {
                    Try {
                        $ConfigJson = $virtualServer | ConvertTo-Json -Depth 10
                        New-NsxtLBVirtualServer -virtualServerName $virtualServer.display_name -json $ConfigJson
                    }
                    Catch {
                        Debug-ExceptionWriter -object $_
                    }
                }
            }
            else {
                Write-Error "Aborting remainder of NSX-T Load Balancer configuration until certificate files present"
            }
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Copy-vRealizeLoadBalancer

Function New-vRealizeLoadBalancerSpec
{
    Param (
        [Parameter (Mandatory = $true)] [Array]$xintSegmentDetails,
        [Parameter (Mandatory = $true)] [Array]$serviceInterfaceIp,
        [Parameter (Mandatory = $true)] [Array]$wsaDetailsObject,
        [Parameter (Mandatory = $false)] [Array]$vraDetailsObject,
        [Parameter (Mandatory = $false)] [Array]$vropsDetailsObject,
        [Parameter (Mandatory = $true)] [String]$wsaCertName,
        [Parameter (Mandatory = $true)] [String]$t1Name,
        [Parameter (Mandatory = $true)] [String]$lbName,
        [Parameter (Mandatory = $true)] [String]$siName,
        [Parameter (Mandatory = $true)] [String]$segmentID
    )

    $xintSegmentName = $xintSegmentDetails.name
    $xintSegmentServiceInterfacePrefixLength = cidrMaskLookup -source mask -value $xintSegmentDetails.subnetMask
    $xintSegmentNextHopIP = $xintSegmentDetails.gateway

    $xintWsaVip = $wsaDetailsObject.loadBalancerIpAddress
    $xintWsaNode1Ip = $wsaDetailsObject.node1IpAddress
    $xintWsaNode2Ip = $wsaDetailsObject.node2IpAddress
    $xintWsaNode3Ip = $wsaDetailsObject.node3IpAddress
    $xintWsaNode1Name = $wsaDetailsObject.fqdn[0].split(".")[0]
    $xintWsaNode2Name = $wsaDetailsObject.fqdn[1].split(".")[0]
    $xintWsaNode3Name = $wsaDetailsObject.fqdn[2].split(".")[0]

    If ($vropsDetailsObject)
    {
        $xintVropsVip = $vropsDetailsObject.loadBalancerIpAddress
        $xintVropsNode1Ip = $vropsDetailsObject.node1IpAddress
        $xintVropsNode2Ip = $vropsDetailsObject.node2IpAddress
        $xintVropsNode3Ip = $vropsDetailsObject.node3IpAddress
        $xintVropsNode1Name = $vropsDetailsObject.fqdn[0].split(".")[0]
        $xintVropsNode2Name = $vropsDetailsObject.fqdn[1].split(".")[0]
        $xintVropsNode3Name = $vropsDetailsObject.fqdn[2].split(".")[0]    
    }

    If ($vraDetailsObject)
    {
        $xintVraVip = $vraDetailsObject.loadBalancerIpAddress
        $xintVraNode1Ip = $vraDetailsObject.node1IpAddress
        $xintVraNode2Ip = $vraDetailsObject.node2IpAddress
        $xintVraNode3Ip = $vraDetailsObject.node3IpAddress
        $xintVraNode1Name = $vraDetailsObject.fqdn[0].split(".")[0]
        $xintVraNode2Name = $vraDetailsObject.fqdn[1].split(".")[0]
        $xintVraNode3Name = $vraDetailsObject.fqdn[2].split(".")[0]   
    }

    $lbJson += '{'
    $lbJson += '"t1_spec":{'
        $lbJson += '"gw":{'
            $lbJson += '"resource_type": "Tier1",'
            $lbJson += '"id": "<!--REPLACE WITH T1NAME-->",'
            $lbJson += '"force_whitelisting": false,'
            $lbJson += '"tier0_path": ""'
        $lbJson += '},'
        $lbJson += '"service_interface":{'
            $lbJson += '"segment_path": "/global-infra/segments/<!--REPLACE WITH SEGMENTID-->",'
            $lbJson += '"id": "<!--REPLACE WITH siName-->",'
            $lbJson += '"overridden": false,'
            $lbJson += '"subnets": ['
            $lbJson += '{'
            $lbJson += '"ip_addresses": ['
            $lbJson += '"<!--REPLACE WITH SI IP-->"'
            $lbJson += '],'
            $lbJson += '"prefix_len": <!--REPLACE WITH SI PREFIX-->'
            $lbJson += '}'
            $lbJson += ']'
        $lbJson += '},'
        $lbJson += '"static_routes":{'
            $lbJson += '"network": "0.0.0.0/0",'
            $lbJson += '"next_hops": ['
                $lbJson += '{'
                    $lbJson += '"ip_address": "<!--REPLACE WITH NEXT HOP IP-->",'
                    $lbJson += '"admin_distance": 1,'
                    $lbJson += '"scope": ['
                        $lbJson += '"/infra/tier-1s/<!--REPLACE WITH T1NAME-->/locale-services/default/interfaces/<!--REPLACE WITH siName-->"'
                    $lbJson += ']           '
                $lbJson += '}'
            $lbJson += '],'
            $lbJson += '"display_name": "default"'
        $lbJson += '}'
    $lbJson += '},'
        $lbJson += '"lb_spec": {'
            $lbJson += '"lb_service": ['
                $lbJson += '{'
                    $lbJson += '"display_name": "<!--REPLACE WITH LB NAME-->",'
                    $lbJson += '"resource_type": "LBService",'
                    $lbJson += '"enabled": true,'
                    $lbJson += '"size": "SMALL",'
                    $lbJson += '"connectivity_path":""'
                $lbJson += '}'
            $lbJson += '],'
            $lbJson += '"service_monitors": ['
            If ($vropsDetailsObject)
                {
                    $lbJson += '{'
                        $lbJson += '"display_name": "vrops-https-monitor",'
                        $lbJson += '"description": "vRealize Operations Manager HTTPS Monitor",'
                        $lbJson += '"resource_type": "LBHttpsMonitorProfile",'
                        $lbJson += '"monitor_port": "443",'
                        $lbJson += '"interval": "5",'
                        $lbJson += '"fall_count": "3",'
                        $lbJson += '"rise_count": "3",'
                        $lbJson += '"timeout": "16",'
                        $lbJson += '"request_method": "GET",'
                        $lbJson += '"request_url": "/suite-api/api/deployment/node/status?services=api&services=adminui&services=ui",'
                        $lbJson += '"request_version": "HTTP_VERSION_1_1",'
                        $lbJson += '"response_status_codes": ['
                            $lbJson += '"200","204","301"'
                        $lbJson += '],'
                        $lbJson += '"response_body": "ONLINE",'
                        $lbJson += '"server_ssl_profile_binding": {'
                            $lbJson += '"ssl_profile_path": "/infra/lb-server-ssl-profiles/default-balanced-server-ssl-profile"'
                        $lbJson += '}'
                    $lbJson += '},'
                }
                If ($vraDetailsObject)
                {
                    $lbJson += '{'
                        $lbJson += '"display_name": "vra-http-monitor",'
                        $lbJson += '"description": "vRealize Automation HTTP Monitor",'
                        $lbJson += '"resource_type": "LBHttpMonitorProfile",'
                        $lbJson += '"monitor_port": "8008",'
                        $lbJson += '"interval": "3",'
                        $lbJson += '"fall_count": "3",'
                        $lbJson += '"rise_count": "3",'
                        $lbJson += '"timeout": "10",'
                        $lbJson += '"request_method": "GET",'
                        $lbJson += '"request_url": "/health",'
                        $lbJson += '"request_version": "HTTP_VERSION_1_1",'
                        $lbJson += '"response_status_codes": ['
                            $lbJson += '"200"'
                        $lbJson += '],'
                        $lbJson += '"response_body": ""'
                    $lbJson += '},'
                }
                $lbJson += '{'
                    $lbJson += '"display_name": "wsa-https-monitor",'
                    $lbJson += '"description": "Clustered Workspace ONE Access HTTPS Monitor",'
                    $lbJson += '"resource_type": "LBHttpsMonitorProfile",'
                    $lbJson += '"monitor_port": "443",'
                    $lbJson += '"interval": "3",'
                    $lbJson += '"fall_count": "3",'
                    $lbJson += '"rise_count": "3",'
                    $lbJson += '"timeout": "10",'
                    $lbJson += '"request_method": "GET",'
                    $lbJson += '"request_url": "/SAAS/API/1.0/REST/system/health/heartbeat",'
                    $lbJson += '"request_version": "HTTP_VERSION_1_1",'
                    $lbJson += '"response_status_codes": ['
                        $lbJson += '"200","201"'
                    $lbJson += '],'
                    $lbJson += '"response_body": "ok",'
                    $lbJson += '"server_ssl_profile_binding": {'
                        $lbJson += '"client_certificate_path": "/infra/certificates/<!--REPLACE WITH XREG WSA CERT-->",'
                        $lbJson += '"ssl_profile_path": "/infra/lb-server-ssl-profiles/default-balanced-server-ssl-profile"'
                    $lbJson += '}'
                $lbJson += '}'
            $lbJson += '],'
            $lbJson += '"app_profiles": ['
            If ($vropsDetailsObject)
            {
                $lbJson += '{'
                    $lbJson += '"display_name": "vrops-http-app-profile-redirect",'
                    $lbJson += '"description": "Cross-Instance vRealize Operations Manager redirect HTTP to HTTPs",'
                    $lbJson += '"resource_type": "LBHttpProfile",'
                    $lbJson += '"idle_timeout": "1800",'
                    $lbJson += '"request_header_size": "1024",'
                    $lbJson += '"response_header_size": "4096",'
                    $lbJson += '"http_redirect_to_https": "True",'
                    $lbJson += '"response_timeout": "60",'
                    $lbJson += '"ntlm": "False"'
                $lbJson += '},'
                $lbJson += '{'
                    $lbJson += '"display_name": "vrops-tcp-app-profile",'
                    $lbJson += '"description": "vRealize Operations Manager TCP App Profile",'
                    $lbJson += '"resource_type": "LBFastTcpProfile",'
                    $lbJson += '"idle_timeout": "1800",'
                    $lbJson += '"ha_flow_mirroring_enabled": "False",'
                    $lbJson += '"close_timeout": "8"'
                $lbJson += '},'
            }
            If ($vraDetailsObject)
            {
                $lbJson += '{'
                    $lbJson += '"display_name": "vra-tcp-app-profile",'
                    $lbJson += '"description": "vRealize Automation TCP App Profile",'
                    $lbJson += '"resource_type": "LBFastTcpProfile",'
                    $lbJson += '"idle_timeout": "1800",'
                    $lbJson += '"ha_flow_mirroring_enabled": "False",'
                    $lbJson += '"close_timeout": "8"'
                $lbJson += '},'
                $lbJson += '{'
                    $lbJson += '"display_name": "vra-http-app-profile-redirect",'
                    $lbJson += '"description": "vRealize Automation Profile to redirect HTTP to HTTPs",'
                    $lbJson += '"resource_type": "LBHttpProfile",'
                    $lbJson += '"idle_timeout": "1800",'
                    $lbJson += '"request_header_size": "1024",'
                    $lbJson += '"response_header_size": "4096",'
                    $lbJson += '"http_redirect_to_https": "True",'
                    $lbJson += '"response_timeout": "60",'
                    $lbJson += '"ntlm": "False"'
                $lbJson += '},'
            }
                $lbJson += '{'
                    $lbJson += '"display_name": "wsa-http-app-profile",'
                    $lbJson += '"description": "Clustered Workspace ONE Access HTTP Redirect",'
                    $lbJson += '"resource_type": "LBHttpProfile",'
                    $lbJson += '"idle_timeout": "3600",'
                    $lbJson += '"x_forwarded_for": "INSERT",'
                    $lbJson += '"request_header_size": "1024",'
                    $lbJson += '"response_header_size": "4096",'
                    $lbJson += '"http_redirect_to_https": "False",'
                    $lbJson += '"response_timeout": "60",'
                    $lbJson += '"ntlm": "False"'
                $lbJson += '},'
                $lbJson += '{'
                    $lbJson += '"display_name": "wsa-http-app-profile-redirect",'
                    $lbJson += '"description": "Clustered Workspace ONE Access redirect HTTP to HTTPs",'
                    $lbJson += '"resource_type": "LBHttpProfile",'
                    $lbJson += '"idle_timeout": "3600",'
                    $lbJson += '"request_header_size": "1024",'
                    $lbJson += '"response_header_size": "4096",'
                    $lbJson += '"http_redirect_to_https": "True",'
                    $lbJson += '"response_timeout": "60",'
                    $lbJson += '"ntlm": "False"'
                $lbJson += '}'
            $lbJson += '],'
            $lbJson += '"persistence_profiles": ['
            If ($vropsDetailsObject)
            {
                $lbJson += '{'
                    $lbJson += '"display_name": "vrops-source-ip-persistence-profile",'
                    $lbJson += '"description": "vRealize Operations Manager Analytics Cluster Source IP Persistence Profile",'
                    $lbJson += '"resource_type": "LBSourceIpPersistenceProfile",'
                    $lbJson += '"persistence_shared": "False",'
                    $lbJson += '"purge": "FULL",'
                    $lbJson += '"ha_persistence_mirroring_enabled": "False"'
                $lbJson += '},'
            }
                $lbJson += '{'
                    $lbJson += '"display_name": "wsa-cookie-persistence-profile",'
                    $lbJson += '"description": "Cookie Persistence Profile",'
                    $lbJson += '"resource_type": "LBCookiePersistenceProfile",'
                    $lbJson += '"persistence_shared": "False",'
                    $lbJson += '"cookie_mode": "REWRITE",'
                    $lbJson += '"cookie_name": "JSESSIONID",'
                    $lbJson += '"cookie_fallback": "True",'
                    $lbJson += '"cookie_garble": "True"'
                $lbJson += '}'
            $lbJson += '],'
            $lbJson += '"pools": ['
            If ($vropsDetailsObject)
            {
                $lbJson += '{'
                    $lbJson += '"display_name": "vrops-server-pool",'
                    $lbJson += '"description": "vRealize Operations Manager Analytics Cluster Server Pool",'
                    $lbJson += '"algorithm": "LEAST_CONNECTION",'
                    $lbJson += '"active_monitor_paths": ['
                        $lbJson += '"/infra/lb-monitor-profiles/vrops-https-monitor"'
                    $lbJson += '],'
                    $lbJson += '"snat_translation": {'
                        $lbJson += '"type": "LBSnatAutoMap"'
                    $lbJson += '},'
                    $lbJson += '"members": ['
                        $lbJson += '{'
                            $lbJson += '"display_name": "<!--REPLACE WITH VROPS NODE 1 NAME-->",'
                            $lbJson += '"backup_member": "false",'
                            $lbJson += '"weight": 1,'
                            $lbJson += '"admin_state": "ENABLED",'
                            $lbJson += '"ip_address": "<!--REPLACE WITH VROPS NODE 1 IP-->",'
                            $lbJson += '"port": "443"'
                        $lbJson += '},'
                        $lbJson += '{'
                            $lbJson += '"display_name": "<!--REPLACE WITH VROPS NODE 2 NAME-->",'
                            $lbJson += '"backup_member": "false",'
                            $lbJson += '"weight": 1,'
                            $lbJson += '"admin_state": "ENABLED",'
                            $lbJson += '"ip_address": "<!--REPLACE WITH VROPS NODE 2 IP-->",'
                            $lbJson += '"port": "443"'
                        $lbJson += '},'
                        $lbJson += '{'
                            $lbJson += '"display_name": "<!--REPLACE WITH VROPS NODE 3 NAME-->",'
                            $lbJson += '"backup_member": "false",'
                            $lbJson += '"weight": 1,'
                            $lbJson += '"admin_state": "ENABLED",'
                            $lbJson += '"ip_address": "<!--REPLACE WITH VROPS NODE 3 IP-->",'
                            $lbJson += '"port": "443"'
                        $lbJson += '}'
                    $lbJson += ']'
                $lbJson += '},'
            }
            If ($vraDetailsObject)
            {    
                $lbJson += '{'
                    $lbJson += '"display_name": "vra-server-pool",'
                    $lbJson += '"description": "vRealize Automation Cluster Pool",'
                    $lbJson += '"algorithm": "LEAST_CONNECTION",'
                    $lbJson += '"active_monitor_paths": ['
                        $lbJson += '"/infra/lb-monitor-profiles/vra-http-monitor"'
                        $lbJson += '],'
                    $lbJson += '"snat_translation": {'
                        $lbJson += '"type": "LBSnatAutoMap"'
                    $lbJson += '},'
                    $lbJson += '"members": ['
                        $lbJson += '{'
                            $lbJson += '"display_name": "<!--REPLACE WITH VRA NODE 1 NAME-->",'
                            $lbJson += '"backup_member": "false",'
                            $lbJson += '"weight": 1,'
                            $lbJson += '"admin_state": "ENABLED",'
                            $lbJson += '"ip_address": "<!--REPLACE WITH VRA NODE 1 IP-->",'
                            $lbJson += '"port": "443"'
                        $lbJson += '},'
                        $lbJson += '{'
                            $lbJson += '"display_name": "<!--REPLACE WITH VRA NODE 2 NAME-->",'
                            $lbJson += '"backup_member": "false",'
                            $lbJson += '"weight": 1,'
                            $lbJson += '"admin_state": "ENABLED",'
                            $lbJson += '"ip_address": "<!--REPLACE WITH VRA NODE 2 IP-->",'
                            $lbJson += '"port": "443"'
                        $lbJson += '},'
                        $lbJson += '{'
                            $lbJson += '"display_name": "<!--REPLACE WITH VRA NODE 3 NAME-->",'
                            $lbJson += '"backup_member": "false",'
                            $lbJson += '"weight": 1,'
                            $lbJson += '"admin_state": "ENABLED",'
                            $lbJson += '"ip_address": "<!--REPLACE WITH VRA NODE 3 IP-->",'
                            $lbJson += '"port": "443"'
                        $lbJson += '}'
                    $lbJson += ']'
                $lbJson += '},'
            }
                $lbJson += '{'
                    $lbJson += '"display_name": "wsa-server-pool",'
                    $lbJson += '"description": "Clustered Workspace ONE Access Server Pool",'
                    $lbJson += '"algorithm": "LEAST_CONNECTION",'
                    $lbJson += '"active_monitor_paths": ['
                        $lbJson += '"/infra/lb-monitor-profiles/wsa-https-monitor"'
                    $lbJson += '],'
                    $lbJson += '"snat_translation": {'
                        $lbJson += '"type": "LBSnatAutoMap"'
                    $lbJson += '},'
                    $lbJson += '"members": ['
                        $lbJson += '{'
                            $lbJson += '"display_name": "<!--REPLACE WITH WSA NODE 1 NAME-->",'
                            $lbJson += '"backup_member": "false",'
                            $lbJson += '"weight": 1,'
                            $lbJson += '"admin_state": "ENABLED",'
                            $lbJson += '"ip_address": "<!--REPLACE WITH WSA NODE 1 IP-->",'
                            $lbJson += '"port": "443"'
                        $lbJson += '},'
                        $lbJson += '{'
                            $lbJson += '"display_name": "<!--REPLACE WITH WSA NODE 2 NAME-->",'
                            $lbJson += '"backup_member": "false",'
                            $lbJson += '"weight": 1,'
                            $lbJson += '"admin_state": "ENABLED",'
                            $lbJson += '"ip_address": "<!--REPLACE WITH WSA NODE 2 IP-->",'
                            $lbJson += '"port": "443"'
                        $lbJson += '},'
                        $lbJson += '{'
                            $lbJson += '"display_name": "<!--REPLACE WITH WSA NODE 3 NAME-->",'
                            $lbJson += '"backup_member": "false",'
                            $lbJson += '"weight": 1,'
                            $lbJson += '"admin_state": "ENABLED",'
                            $lbJson += '"ip_address": "<!--REPLACE WITH WSA NODE 3 IP-->",'
                            $lbJson += '"port": "443"'
                        $lbJson += '}'
                    $lbJson += ']'
                $lbJson += '}'
            $lbJson += '],'
            $lbJson += '"virtual_servers": ['
            If ($vropsDetailsObject)
            {
                $lbJson += '{'
                    $lbJson += '"display_name": "vrops-https",'
                    $lbJson += '"description": "vRealize Operations Manager Analytics Cluster UI",'
                    $lbJson += '"resource_type": "LBVirtualServer",'
                    $lbJson += '"enabled": "true",'
                    $lbJson += '"lb_persistence_profile_path": "/infra/lb-persistence-profiles/vrops-source-ip-persistence-profile",'
                    $lbJson += '"application_profile_path": "/infra/lb-app-profiles/vrops-tcp-app-profile",'
                    $lbJson += '"pool_path": "/infra/lb-pools/vrops-server-pool",'
                    $lbJson += '"lb_service_path": "/infra/lb-services/<!--REPLACE WITH LB NAME-->",'
                    $lbJson += '"ip_address": "<!--REPLACE WITH VROPS VIP-->",'
                    $lbJson += '"ports": ['
                        $lbJson += '"443"'
                    $lbJson += ']'
                $lbJson += '},'
                $lbJson += '{'
                    $lbJson += '"display_name": "vrops-http-redirect",'
                    $lbJson += '"description": "vRealize Operations Manager Analytics Cluster HTTP to HTTPS Redirect",'
                    $lbJson += '"resource_type": "LBVirtualServer",'
                    $lbJson += '"enabled": "true",'
                    $lbJson += '"application_profile_path": "/infra/lb-app-profiles/vrops-http-app-profile-redirect",'
                    $lbJson += '"lb_service_path": "/infra/lb-services/<!--REPLACE WITH LB NAME-->",'
                    $lbJson += '"ip_address": "<!--REPLACE WITH VROPS VIP-->",'
                    $lbJson += '"ports": ['
                        $lbJson += '"80"'
                    $lbJson += ']'
                $lbJson += '},'
            }
            If ($vraDetailsObject)
            {
                $lbJson += '{'
                    $lbJson += '"display_name": "vra-https",'
                    $lbJson += '"description": "vRealize Automation Cluster UI",'
                    $lbJson += '"resource_type": "LBVirtualServer",'
                    $lbJson += '"enabled": "true",'
                    $lbJson += '"application_profile_path": "/infra/lb-app-profiles/vra-tcp-app-profile",'
                    $lbJson += '"pool_path": "/infra/lb-pools/vra-server-pool",'
                    $lbJson += '"lb_service_path": "/infra/lb-services/<!--REPLACE WITH LB NAME-->",'
                    $lbJson += '"ip_address": "<!--REPLACE WITH VRA VIP-->",'
                    $lbJson += '"ports": ['
                        $lbJson += '"443"'
                    $lbJson += ']'
                $lbJson += '},'
                $lbJson += '{'
                    $lbJson += '"display_name": "vra-http-redirect",'
                    $lbJson += '"description": "vRealize Automation HTTP to HTTPS Redirect",'
                    $lbJson += '"resource_type": "LBVirtualServer",'
                    $lbJson += '"enabled": "true",'
                    $lbJson += '"application_profile_path": "/infra/lb-app-profiles/vra-http-app-profile-redirect",'
                    $lbJson += '"lb_service_path": "/infra/lb-services/<!--REPLACE WITH LB NAME-->",'
                    $lbJson += '"ip_address": "<!--REPLACE WITH VRA VIP-->",'
                    $lbJson += '"ports": ['
                        $lbJson += '"80"'
                    $lbJson += ']'
                $lbJson += '},'
            }
                $lbJson += '{'
                    $lbJson += '"display_name": "wsa-https",'
                    $lbJson += '"description": "Clustered Workspace ONE Access Cluster UI",'
                    $lbJson += '"resource_type": "LBVirtualServer",'
                    $lbJson += '"enabled": "true",'
                    $lbJson += '"lb_persistence_profile_path": "/infra/lb-persistence-profiles/wsa-cookie-persistence-profile",'
                    $lbJson += '"application_profile_path": "/infra/lb-app-profiles/wsa-http-app-profile",'
                    $lbJson += '"pool_path": "/infra/lb-pools/wsa-server-pool",'
                    $lbJson += '"lb_service_path": "/infra/lb-services/<!--REPLACE WITH LB NAME-->",'
                    $lbJson += '"ip_address": "<!--REPLACE WITH WSA VIP-->",'
                    $lbJson += '"ports": ['
                        $lbJson += '"443"'
                    $lbJson += '],'
                    $lbJson += '"client_ssl_profile_binding": {'
                        $lbJson += '"default_certificate_path": "/infra/certificates/<!--REPLACE WITH XREG WSA CERT-->",'
                        $lbJson += '"ssl_profile_path": "/infra/lb-client-ssl-profiles/default-balanced-client-ssl-profile"'
                    $lbJson += '},'
                    $lbJson += '"server_ssl_profile_binding": {'
                        $lbJson += '"client_certificate_path": "/infra/certificates/<!--REPLACE WITH XREG WSA CERT-->",'
                        $lbJson += '"ssl_profile_path": "/infra/lb-server-ssl-profiles/default-balanced-server-ssl-profile"'
                    $lbJson += '},'
                    $lbJson += '"rules": ['
                        $lbJson += '{'
                            $lbJson += '"match_strategy": "ALL",'
                            $lbJson += '"phase": "HTTP_REQUEST_REWRITE",'
                            $lbJson += '"actions": ['
                                $lbJson += '{'
                                    $lbJson += '"type": "LBHttpRequestHeaderRewriteAction",'
                                    $lbJson += '"header_name": "Remoteport",'
                                    $lbJson += '"header_value": "$_remote_port"'
                                $lbJson += '}'
                            $lbJson += ']'
                        $lbJson += '}'
                    $lbJson += ']'
                $lbJson += '},'
                $lbJson += '{'
                    $lbJson += '"display_name": "wsa-http-redirect",'
                    $lbJson += '"description": "Clustered Workspace ONE Access Cluster HTTP to HTTPS Redirect",'
                    $lbJson += '"resource_type": "LBVirtualServer",'
                    $lbJson += '"enabled": "true",'
                    $lbJson += '"application_profile_path": "/infra/lb-app-profiles/wsa-http-app-profile-redirect",'
                    $lbJson += '"lb_service_path": "/infra/lb-services/<!--REPLACE WITH LB NAME-->",'
                    $lbJson += '"ip_address": "<!--REPLACE WITH WSA VIP-->",'
                    $lbJson += '"ports": ['
                        $lbJson += '"80"'
                    $lbJson += ']'
                $lbJson += '}'
            $lbJson += ']'
        $lbJson += '}'
    $lbJson += '}'

    $lbJson = $lbJson | ForEach-Object { $_ `
            -replace '<!--REPLACE WITH T1NAME-->', $t1Name `
            -replace '<!--REPLACE WITH xintSegmentName-->', $xintSegmentName `
            -replace '<!--REPLACE WITH SEGMENTID-->', $segmentID `
            -replace '<!--REPLACE WITH siName-->', $siName `
            -replace '<!--REPLACE WITH SI IP-->', $serviceInterfaceIp `
            -replace '<!--REPLACE WITH XREGION CIDR-->', $xintionVXLAN `
            -replace '<!--REPLACE WITH NEXT HOP IP-->', $xintSegmentNextHopIP `
            -replace '<!--REPLACE WITH SI PREFIX-->', $xintSegmentServiceInterfacePrefixLength `
            -replace '<!--REPLACE WITH LB NAME-->', $lbName `
            -replace '<!--REPLACE WITH XREG WSA CERT-->', $wsaCertName `
            -replace '<!--REPLACE WITH WSA NODE 1 NAME-->', $xintWsaNode1Name `
            -replace '<!--REPLACE WITH WSA NODE 2 NAME-->', $xintWsaNode2Name `
            -replace '<!--REPLACE WITH WSA NODE 3 NAME-->', $xintWsaNode3Name `
            -replace '<!--REPLACE WITH WSA NODE 1 IP-->', $xintWsaNode1IP `
            -replace '<!--REPLACE WITH WSA NODE 2 IP-->', $xintWsaNode2IP `
            -replace '<!--REPLACE WITH WSA NODE 3 IP-->', $xintWsaNode3IP `
            -replace '<!--REPLACE WITH VROPS NODE 1 NAME-->', $xintVropsNode1Name `
            -replace '<!--REPLACE WITH VROPS NODE 2 NAME-->', $xintVropsNode2Name `
            -replace '<!--REPLACE WITH VROPS NODE 3 NAME-->', $xintVropsNode3Name `
            -replace '<!--REPLACE WITH VROPS NODE 1 IP-->', $xintVropsNode1Ip `
            -replace '<!--REPLACE WITH VROPS NODE 2 IP-->', $xintVropsNode2Ip `
            -replace '<!--REPLACE WITH VROPS NODE 3 IP-->', $xintVropsNode3Ip `
            -replace '<!--REPLACE WITH VRA NODE 1 NAME-->', $xintVraNode1Name `
            -replace '<!--REPLACE WITH VRA NODE 2 NAME-->', $xintVraNode2Name `
            -replace '<!--REPLACE WITH VRA NODE 3 NAME-->', $xintVraNode3Name `
            -replace '<!--REPLACE WITH VRA NODE 1 IP-->', $xintVraNode1Ip `
            -replace '<!--REPLACE WITH VRA NODE 2 IP-->', $xintVraNode2Ip `
            -replace '<!--REPLACE WITH VRA NODE 3 IP-->', $xintVraNode3Ip `
            -replace '<!--REPLACE WITH WSA VIP-->', $xintWsaVip `
            -replace '<!--REPLACE WITH VROPS VIP-->', $xintVropsVip `
            -replace '<!--REPLACE WITH VRA VIP-->', $xintVraVip `
    }
    $lbCustomObject = $lbJson | ConvertFrom-Json
    Return $lbCustomObject
}
Export-ModuleMember -Function New-vRealizeLoadBalancerSpec

Function Get-NsxtGlobalSegmentID
{
    Param (
        [Parameter (Mandatory=$true)]
            [String]$segmentName
    )

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/global-infra/segments/"

        $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
        $segmentObjectId = ($response.results | where-object {$_.display_name -eq $segmentName}).id
    }
    Catch {
        Write-Error $_.Exception.Message
    }
    Return $segmentObjectId
}
Export-ModuleMember -Function Get-NsxtGlobalSegmentID

Function Add-CertToNsxCertificateStore 
{
    Param (
        [Parameter (Mandatory = $true)] [String]$certName 
    )

    Try {
        $pemFile = Get-ExternalFileName -title "Select the Certificate Chain PEM File for Clustered WSA (.pem)" -fileType "pem" -location "default"
    }
    Catch {
        Write-Error $_.Exception.Message
    }
    Try {
        $keyFile = Get-ExternalFileName -title "Select the Key File for Clustered WSA (.key)" -fileType "key" -location "default"
    }
    Catch {
        Write-Error $_.Exception.Message
    }
    
    $certAlreadyImported = ""
    
    #check for existing certificate
    Try {
        $certAlreadyImported = Get-NsxtCertificate -certificateName $certName -ErrorAction SilentlyContinue
    }
    Catch {
        $certAlreadyImported = $false
    }
    
    # report on existing cert or install new cert
    if ($certAlreadyImported) {
        $wsaCertPresent = $true
    }
    else {
            $pemContent = (Get-Content $pemFile) -join "\n"
            $keyContent = (Get-Content $keyFile) -join "\n"
            $body = 
            '{
              "pem_encoded": "<!--REPLACE WITH PEM DATA-->",
              "private_key": "<!--REPLACE WITH KEY DATA-->" 
            }
            '
            $body = $body | ForEach-Object { $_ `
                    -replace '<!--REPLACE WITH PEM DATA-->', $pemContent `
                    -replace '<!--REPLACE WITH KEY DATA-->', $keyContent `
            }
            Try {
                Set-NsxtCertificate -certificateName $certName -json $body
                $wsaCertPresent = $true
            }
            Catch {
                Debug-ExceptionWriter -object $_
            }   
    }
    Return $wsaCertPresent
}
Export-ModuleMember -Function Add-CertToNsxCertificateStore

Function Get-NsxtEdgeCluster
{
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Gets NSX-T Edge Cluster Id
    
        .DESCRIPTION
        The Get-NsxtEdgeCluster cmdlet gets the Edge Cluster Id
    
        .EXAMPLE
        PS C:\> Get-NsxtEdgeCluster
        This example creates a new Route Map on a Tier 0 Gateway
    #>

    Try {
        $uri = "https://$nsxtmanager/api/v1/edge-clusters"
        $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
        $response.results
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtEdgeCluster

Function New-NsxtTier1
{
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Creates a Tier 1 Gateway
    
        .DESCRIPTION
        The New-NsxtTier1 cmdlet creates a Teir 1 Gateway
    
        .EXAMPLE
        PS C:\> New-NsxtTier1 -tier1Gateway sfo-w01-ec01-t0-lb01 -json $ConfigJson
        This example creates a new Tier 1 Gateway
    #>

    Param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$tier1Gateway,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$json
    )

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/infra/tier-1s/$($tier1Gateway)"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -headers $nsxtHeaders -body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtTier1

Function Set-NsxtTier1
{
        <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Configures Tier 1 Gateway
    
        .DESCRIPTION
        The Set-NsxtTier1 cmdlet configures a Tier 1 Gateway
    
        .EXAMPLE
        PS C:\> Set-NsxtTier1 -tier1Gateway -json
        This example sets the configuration on a Tier 1 Gateway
    #>

    Param (
        [Parameter (Mandatory=$true)]
            [String]$tier1Gateway,
        [Parameter (Mandatory=$true)]
            [String]$json
    )
      
    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/infra/tier-1s/$($tier1Gateway)/locale-services/default"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -headers $nsxtHeaders -body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-NsxtTier1

Function New-NsxtTier1ServiceInterface 
{
       <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Creates Service Interface on Tier 1 Gateway
    
        .DESCRIPTION
        The New-NsxtTier1ServiceInterface cmdlet configures a Service Interface on Tier 1 Gateway
    
        .EXAMPLE
        PS C:\> New-NsxtTier1ServiceInterface -tier1Gateway -interfaceId -json
        This example configures a Service Interface on a Tier 1 Gateway
    #>

    Param (
        [Parameter (Mandatory=$true)]
            [String]$tier1Gateway,
        [Parameter (Mandatory=$true)]
            [String]$interfaceId,
        [Parameter (Mandatory=$true)]
            [String]$json
    )

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/infra/tier-1s/$($tier1Gateway)/locale-services/default/interfaces/$($interfaceId)"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -headers $nsxtHeaders -body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtTier1ServiceInterface

Function New-NsxtTier1StaticRoute 
{
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Creates Static Route on Tier 1 Gateway
    
        .DESCRIPTION
        The New-New-NsxtTier1StaticRoute cmdlet creates a static route on Tier 1 Gateway
    
        .EXAMPLE
        PS C:\> New-NsxtTier1StaticRoute -tier1Gateway -segment -json
        This example configures a Service Interface on a Tier 1 Gateway
    #>
    Param (
        [Parameter (Mandatory=$true)]
            [String]$tier1Gateway,
        [Parameter (Mandatory=$true)]
            [String]$segment,
        [Parameter (Mandatory=$true)]
            [String]$json
    )

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/infra/tier-1s/$($tier1Gateway)/static-routes/$($segment)"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -headers $nsxtHeaders -body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtTier1StaticRoute

Function New-NsxtLoadBalancer 
{
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Creates a Load Balancer 
    
        .DESCRIPTION
        The New-NsxtLoadBalancer cmdlet creates a load balancer 
    
        .EXAMPLE
        PS C:\> New-NsxtLoadBalancer -lbName -json
        This example creates a load balancer
    #>
    Param (
        [Parameter (Mandatory=$true)]
            [String]$lbName,
        [Parameter (Mandatory=$true)]
            [String]$json
    )

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/infra/lb-services/$($lbName)"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -headers $nsxtHeaders -body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtLoadBalancer

Function New-NsxtLBServiceMonitor 
{ 
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Creates a Load Balancer Service Monitor
    
        .DESCRIPTION
        The New-NsxtLBServiceMonitor cmdlet creates a Load Balancer Service Monitor
    
        .EXAMPLE
        PS C:\> New-NsxtLBServiceMonitor -monitorName -json
        This example creates a Load Balancer Serviec Monitor
    #>
    Param (
        [Parameter (Mandatory=$true)]
            [String]$monitorName,
        [Parameter (Mandatory=$true)]
            [String]$json
    )

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/infra/lb-monitor-profiles/$($monitorName)"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -headers $nsxtHeaders -body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtLBServiceMonitor

Function New-NsxtLBAppProfile 
{
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Creates a Load Balancer Application Profile
    
        .DESCRIPTION
        The New-NsxtLBAppProfile cmdlet creates a Load Balancer Application Profile
    
        .EXAMPLE
        PS C:\> New-NsxtLBAppProfile -appProfileName -json
        This example creates a Load Balancer Application Profile
    #>
    Param (
        [Parameter (Mandatory=$true)]
            [String]$appProfileName,
        [Parameter (Mandatory=$true)]
            [String]$json
    )
    
    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/infra/lb-app-profiles/$($appProfileName)"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -headers $nsxtHeaders -body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtLBAppProfile

Function New-NsxtLBPersistenceAppProfile 
{
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Creates a Load Balancer Persistence Application Profile
    
        .DESCRIPTION
        The New-NsxtLBPersistenceAppProfile cmdlet creates a Load Balancer Persistence Application Profile
    
        .EXAMPLE
        PS C:\> New-NsxtLBPersistenceAppProfile -appProfileName -json
        This example creates a Load Balancer Persistence Application Profile
    #>
    Param (
        [Parameter (Mandatory=$true)]
            [String]$appProfileName,
        [Parameter (Mandatory=$true)]
            [String]$json
    )
    
    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/infra/lb-persistence-profiles/$($appProfileName)"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -headers $nsxtHeaders -body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtLBPersistenceAppProfile

Function New-NsxtLBPool 
{
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Creates a Load Balancer Pool
    
        .DESCRIPTION
        The New-NsxtLBPool cmdlet creates a Load Balancer Pool
    
        .EXAMPLE
        PS C:\> New-NsxtLBPool -poolName -json
        This example creates a Load Balancer Pool
    #>
    Param (
        [Parameter (Mandatory=$true)]
            [String]$poolName,
        [Parameter (Mandatory=$true)]
            [String]$json
    )

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/infra/lb-pools/$($poolName)"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -headers $nsxtHeaders -body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtLBPool

Function New-NsxtLBVirtualServer 
{
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Creates a Load Balancer Virtual Server
    
        .DESCRIPTION
        The New-NsxtLBVirtualServer cmdlet creates a Load Balancer Virtual Server
    
        .EXAMPLE
        PS C:\> New-NsxtLBVirtualServer -virtualServerName -json
        This example creates a Load Balancer Virtual Server
    #>
    Param (
        [Parameter (Mandatory=$true)]
            [String]$virtualServerName,
        [Parameter (Mandatory=$true)]
            [String]$json
    ) 

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/infra/lb-virtual-servers/$($virtualServerName)"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -headers $nsxtHeaders -body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function New-NsxtLBVirtualServer

Function Get-NsxtCertificate
{
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Gets NSX-T Certificates
    
        .DESCRIPTION
        The Get-NsxtCertificates cmdlet gets certificates installed in NSX-T
    
        .EXAMPLE
        PS C:\> Get-NsxtCertificates
        This example gets the certificates installed in NSX-T
    #>

    Param (
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$certificateName
    )

    Try {
        if (!$PsBoundParameters.ContainsKey("certificateName")) {
            $uri = "https://$nsxtmanager/policy/api/v1/infra/certificates"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response.results
        }
        elseif ($PsBoundParameters.ContainsKey("certificateName")) {
            $uri = "https://$nsxtmanager/policy/api/v1/infra/certificates/$($certificateName)"
            $response = Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $nsxtHeaders
            $response
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-NsxtCertificate

Function Set-NsxtCertificate
{
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/08/2020
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Installs a Certificate in NSX-T
    
        .DESCRIPTION
        The Set-NsxtCertificates cmdlet installs certificates in NSX-T
    
        .EXAMPLE
        PS C:\> Set-NsxtCertificates
        This example installs the certificates in NSX-T
    #>

    Param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$certificateName,
        [Parameter (Mandatory=$true)]
            [String]$json
    )

    Try {
        $uri = "https://$nsxtmanager/policy/api/v1/infra/certificates/$($certificateName)"
        $response = Invoke-RestMethod -Method PATCH -URI $uri -ContentType application/json -headers $nsxtHeaders -body $json
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Set-NsxtCertificate

##################  End NSX-T Functions #######################
###############################################################


###############################################################
############  Begin vSphere with Tanzu Functions ##############

Function Request-vSphereApiToken {
    <#
        .SYNOPSIS
        Request an authentication token for the vSphere REST API

        .DESCRIPTION
        The Request-vSphereApiToken cmdlet requests an authentication token for the vSphere REST API

		use -admin to set the Admin token for vCenter Server Management Interface
        .EXAMPLE
        Request-vSphereApiToken -Fqdn sfo-w01-vc01.sfo.rainpole.io -Username administrator@vsphere.local -Password VMw@re1!
        This example requests a vSphere REST API authentication token for user administrator@vsphere.local from vCenter Server sfo-w01-vc01.sfo.rainpole.io

        .EXAMPLE
        Get-vCenterServerDetail -Server sfo-vcf01.sfo.rainpole.io -User administrator@vsphere.local -Pass VMw@re1! -Domain sfo-w01 | Request-vSphereApiToken
        This example requests a vSphere REST API authentication token for user administrator@vsphere.local from the vCenter Server that manages VI workload domain sfo-w01
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Fqdn,
        [Parameter (Mandatory = $false)] [String]$Username,
        [Parameter (Mandatory = $false)] [String]$Password,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psobject]$inputObject,
		[Parameter (Mandatory = $false)] [switch]$admin
    )

    if ($inputObject) {
        $username = $inputObject.ssoAdmin
        $password = $inputObject.ssoAdminPass
        $fqdn = $inputObject.fqdn
        $sddcManager = (Get-VCFManager).fqdn
    }
    else {
        if (!$PsBoundParameters.ContainsKey("username") -or (!$PsBoundParameters.ContainsKey("password"))) {
            # Request Credentials
            $creds = Get-Credential
            $username = $creds.UserName.ToString()
            $password = $creds.GetNetworkCredential().password
        }
        if (!$PsBoundParameters.ContainsKey("fqdn")) {
            $fqdn = Read-Host "vCenter Server FQDN not found. Please enter a value, e.g., sfo-m01-vc01.sfo.rainpole.io"
        }
    }
    $vcAuthHeaders = createvCenterAuthHeader($username, $password)

    # Perform the vCenter REST API call to authenticate and retrieve the session token
    Try {
		if ($admin){
			$tmp = $fqdn
			$fqdn = $fqdn + ":5480"
			$vcAdminSession = (Invoke-WebRequest -Method POST -URI https://$fqdn/rest/com/vmware/cis/session -Headers $vcAuthHeaders | ConvertFrom-Json).Value
			$fqdn = $tmp
		}
		$vcSession = (Invoke-WebRequest -Method POST -URI https://$fqdn/rest/com/vmware/cis/session -Headers $vcAuthHeaders | ConvertFrom-Json).Value
    }
    Catch {
        Write-Error -Message "Something went wrong with vCenter Server authentication."
    }

    # Use the session token to build the header used from here on
    $Global:vcHeaders = @{"vmware-api-session-id" = $vcSession }
    $Global:vcHeaders.Add("Content-Type", "application/json")

	# Use the session token to build the header for admin interface used from here on
	if ($admin){
		$Global:vcAdminHeaders = @{"vmware-api-session-id" = $vcAdminSession }
		$Global:vcAdminHeaders.Add("Content-Type", "application/json")
	}

    # Validate credentials by executing an API call
    $Global:currentvCenterServer = $Fqdn

    $newUri = "https://$fqdn/api/appliance/system/version"
    $oldUri = "https://$fqdn/rest/appliance/system/version"

    Try {
        # Checking against the vCenter API
        # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
        if ($PSEdition -eq 'Core') {
            Try {
                $response = Invoke-RestMethod -Method GET -Uri $newUri -Headers $vcHeaders -SkipCertificateCheck
                if ($response) {
                    $responseSplit = $response.version.Split(".")
                    $global:vCenterApi = $responseSplit[0..2] -join ""
                }
            }
            Catch {
                $errorStatus = $_.Exception.Response.StatusCode
            }
            if ($errorStatus -eq "NotFound") {
                $response = Invoke-RestMethod -Method GET -Uri $oldUri -Headers $vcHeaders -SkipCertificateCheck
                $responseSplit = $response.value.version.Split(".")
                $global:vCenterApi = $responseSplit[0..2] -join ""
            }
        }
        else {
            Try {
                $response = Invoke-RestMethod -Method GET -Uri $newUri -Headers $vcHeaders

                if ($response) {
                    $responseSplit = $response.version.Split(".")
                    $global:vCenterApi = $responseSplit[0..2] -join ""
                }
            }
            Catch {
                $errorStatus = $_.Exception.Response.StatusCode
            }

            if ($errorStatus -eq "NotFound") {
                $response = Invoke-RestMethod -Method GET -Uri $oldUri -Headers $vcHeaders
                $responseSplit = $response.value.version.Split(".")
                $global:vCenterApi = $responseSplit[0..2] -join ""
            }
        }
        if ($response) {
            if ($inputObject) {
                Write-Output "Successfully Requested New API Token for vCenter Server $fqdn via SDDC Manager $sddcManager"
            }
            else {
                Write-Output "Successfully Requested New API Token for vCenter Server $fqdn"
            }
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Request-vSphereApiToken

Function Enable-WMRegistry {
    <#
        .SYNOPSIS
        Enable the embedded Harbor Registry on a Supervisor Cluster

        .DESCRIPTION
        The Enable-WMRegistry cmdlet enables the embedded Harbor Registry on a Supervisor Cluster

        .EXAMPLE
        Enable-WMRegistry -Cluster "sfo-w01-cl01" -StoragePolicy "vsphere-with-tanzu-policy"
        This example enables the embedded Harbor Registry on Supervisor Cluster "sfo-w01-cl01"

        .EXAMPLE
        Get-WMCluster -Cluster "sfo-w01-cl01" | Enable-WMRegistry
        This example enables the embedded Harbor Registry on Supervisor Cluster "sfo-w01-cl01" via pipeline from Get-WMCluster with the default image storage policy for the Supervisor Cluster
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Domain,
        [Parameter (Mandatory = $false)] [String]$Cluster,
        [Parameter (Mandatory = $false)] [String]$StoragePolicy,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    $vCenterFqdn = $currentvCenterServer

    if ($inputObject) {
        $Cluster = $inputObject.Name
    }

    Try {
        if ($vCenterApi -le 701) {
            $getHarborInstalled = (Invoke-RestMethod -Method GET -URI https://$vCenterFqdn/rest/vcenter/content/registries/harbor -Headers $vcHeaders).value
        }
        elseif ($vCenterApi -ge 702) {
            $getHarborInstalled = Invoke-RestMethod -Method GET -URI https://$vCenterFqdn/api/vcenter/content/registries/harbor -Headers $vcHeaders
        }
    }
    Catch {
        Write-Error = $_.Exception
    }

    if (!$getHarborInstalled) {
        Try {
            $wmClusterId = (Invoke-RestMethod -Method GET -URI  https://$vCenterFqdn/api/vcenter/namespace-management/clusters -Headers $vcHeaders | Where-Object { $_.cluster_name -eq $Cluster }).cluster
        }
        Catch {
            Write-Error $_.Exception.Message
        }

        if (!$StoragePolicy) {
            Try {
                $storagePolicyId = (Invoke-RestMethod -Method GET -URI  https://$vCenterFqdn/api/vcenter/namespace-management/clusters/$wmClusterId -Headers $vcHeaders).image_storage.storage_policy
            }
            Catch {
                Write-Error $_.Exception.Message
            }
        }
        elseif ($StoragePolicy) {
            Try {
                if ($vCenterApi -ge 702) {
                    $storagePolicyId = ((Invoke-WebRequest -Method GET -URI https://$vCenterFqdn/api/vcenter/storage/policies -Headers $vcHeaders | ConvertFrom-Json) | Where-Object { $_.name -eq $StoragePolicy }).policy
                    $json = @"
{
    "cluster" : "$wmClusterId",
    "storage" :
    [
        {
            "policy" : "$storagePolicyId"
        }
    ]
}
"@
                }
                elseif ($vCenterApi -le 701) {
                    $storagePolicyId = ((Invoke-WebRequest -Method GET -URI https://$vCenterFqdn/rest/vcenter/storage/policies -Headers $vcHeaders | ConvertFrom-Json).value | Where-Object { $_.name -eq $StoragePolicy }).policy
                    $json = @"
{
    "spec" :
    {
        "cluster" : "$wmClusterId",
        "storage" :
        [
            {
                "policy" : "$storagePolicyId"
            }
        ]
    }
}
"@
                }
            }
            Catch {
                Write-Error $_.Exception.Message
            }
        }
    }
    # Send a REST API call to vCenter Server to instantiate the new Harbor registry
        if ($vCenterApi -le 701) {
            Try {
                $installHarbor = Invoke-RestMethod -Method POST -URI https://$vCenterFqdn/rest/vcenter/content/registries/harbor -Headers $vcHeaders -Body $json -ContentType application/json
            }
            Catch {
                Write-Error $_.Exception.Message
            }

            if ($installHarbor) {
                $installHarborValue = $installHarbor.value
                Write-Output "Embedded registry $installHarborValue deployment successfully started on Supervisor Cluster $Cluster"
            }
        }
        elseif ($vCenterApi -ge 702) {
            Try {
                $installHarbor = Invoke-RestMethod -Method POST -URI https://$vCenterFqdn/api/vcenter/content/registries/harbor -Headers $vcHeaders -Body $json -ContentType application/json
            }
            Catch {
                Write-Error $_.Exception.Message
            }

            if ($installHarbor) {
                Write-Output "Embedded registry $installHarbor deployment successfully started on Supervisor Cluster $Cluster"
            }
        }
}
Export-ModuleMember -Function Enable-WMRegistry

Function Get-WMRegistry {
    <#
        .SYNOPSIS
        Retrieves the embedded Harbor Registry on a Supervisor Cluster

        .DESCRIPTION
        The Get-WMRegistry cmdlet retrieves the embedded Harbor Registry on a Supervisor Cluster

        .EXAMPLE
        Get-WMRegistry
        This example retrieves all embedded Harbor Registries in vCenter Server inventory

        .EXAMPLE
        Get-WMRegistry -Cluster "sfo-w01-cl01"
        This example enables the embedded Harbor Registry on Supervisor Cluster "sfo-w01-cl01"

        .EXAMPLE
        Get-WMCluster -Cluster "sfo-w01-cl01" | Get-WMRegistry
        This example enables the embedded Harbor Registry on Supervisor Cluster "sfo-w01-cl01" via pipeline from Get-WMCluster
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Cluster,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    $vCenterFqdn = $currentvCenterServer

    if ($inputObject) {
        $Cluster = $inputObject.Name
    }

    if ($Cluster) {
        Try {
            $wmClusterId = (Invoke-RestMethod -Method GET -URI  https://$vCenterFqdn/api/vcenter/namespace-management/clusters -Headers $vcHeaders | Where-Object { $_.cluster_name -eq $Cluster }).cluster
        }
        Catch {
            Write-Error $_.Exception.Message
        }
    }

    Try {
        if (!$PsBoundParameters.ContainsKey("Cluster")) {
            if ($vCenterApi -le 701) {
                $response = Invoke-RestMethod -Method GET -URI https://$vCenterFqdn/rest/vcenter/content/registries/harbor -ContentType application/json -headers $vcHeaders
                $response.value
            }
            elseif ($vCenterApi -ge 702) {
                $response = Invoke-RestMethod -Method GET -URI https://$vCenterFqdn/api/vcenter/content/registries/harbor -ContentType application/json -headers $vcHeaders
                $response
            }
        }
        elseif ($PsBoundParameters.ContainsKey("Cluster")) {
            if ($vCenterApi -le 701) {
                $response = Invoke-RestMethod -Method GET -URI https://$vCenterFqdn/rest/vcenter/content/registries/harbor -ContentType application/json -headers $vcHeaders
                $response.value | Where-Object { $_.cluster -eq $wmClusterId }
            }
            elseif ($vCenterApi -ge 702) {
                $response = Invoke-RestMethod -Method GET -URI https://$vCenterFqdn/api/vcenter/content/registries/harbor -ContentType application/json -headers $vcHeaders
                $response | Where-Object { $_.cluster -eq $wmClusterId }
            }
        }
    }
    Catch {
        Write-Error = $_.Exception
    }
}
Export-ModuleMember -Function Get-WMRegistry

Function Remove-WMRegistry {
    <#
        .SYNOPSIS
        Remove the embedded Harbor Registry on a Supervisor Cluster

        .DESCRIPTION
        The Remove-wmRegistry cmdlet removes the embedded Harbor Registry on a Supervisor Cluster

        .EXAMPLE
        Get-WMRegistry -Cluster "sfo-w01-cl01" | Remove-WMRegistry
        This example enables the embedded Harbor Registry on Supervisor Cluster "sfo-w01-cl01" via pipeline from Get-wmCluster with the default storage policy for the Supervisor Cluster

        .EXAMPLE
        Remove-WMRegistry -Cluster "sfo-w01-cl01"
        This example enables the embedded Harbor Registry on Supervisor Cluster "sfo-w01-cl01" via pipeline from Get-wmCluster with the default storage policy for the Supervisor Cluster
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Cluster,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    $vCenterFqdn = $currentvCenterServer

    if ($inputObject) {
        $harborRegistryId = $inputObject.registry
    }
    else {
        Try {
            $harborRegistryId = (Get-WMRegistry -Cluster $Cluster).registry
        }
        Catch {
            Write-Error $_.Exception.Message
        }
    }

    if ($vCenterApi -le 701) {
        $uri = "https://$vCenterFqdn/rest/vcenter/content/registries/harbor/$harborRegistryId"
    }
    elseif ($vCenterApi -ge 702) {
        $uri = "https://$vCenterFqdn/api/vcenter/content/registries/harbor/$harborRegistryId"
    }

    Try {
        $response = Invoke-WebRequest -Method DELETE -URI $uri -ContentType application/json -headers $vcHeaders
        if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 204) {
            Write-Output "Embedded registry removal successfully started for Supervisor Cluster $Cluster"
        }
    }
    Catch {
        Write-Error = $_.Exception
    }
}
Export-ModuleMember -Function Remove-WMRegistry

Function Connect-WMCluster {
    <#
        .SYNOPSIS
        Log in to a Supervisor Cluster

        .DESCRIPTION
        The Connect-WMCluster cmdlet adds a refix List to an NSX-T Route Map

        .EXAMPLE
        Connect-WMCluster -Cluster sfo-w01-cl01 -User administrator@vsphere.local -Pass VMw@re1!
        This example logs the vSphere SSO user administrator@vsphere.local into Supervisor Cluster sfo-w01-cl01
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Cluster,
        [Parameter (Mandatory = $true)] [String]$User,
        [Parameter (Mandatory = $true)] [String]$Pass,
        [Parameter (ValueFromPipeline, Mandatory = $false)] [psObject]$inputObject
    )

    if ($inputObject) {
        $Server = $inputObject.KubernetesHostname
    }
    else {
        $Server = (Get-WMCluster -Cluster $Cluster).KubernetesHostname
    }

    Try {
        Start-AwaitSession | Out-Null
        Send-AwaitCommand "kubectl vsphere login --server $Server --vsphere-username $Username --insecure-skip-tls-verify" | Out-Null
        Wait-AwaitResponse "Password:" | Out-Null
        Send-AwaitCommand "$Password"
        Stop-AwaitSession
        Start-Sleep -seconds 3 | Out-Null
    }
    Catch {
        Write-Error "Something went wrong."
    }

    $tryKubectl = Invoke-Expression "kubectl get nodes"

    if ($tryKubectl) {
        Write-Output "Connection successful."
    }
}
Export-ModuleMember -Function Connect-WMCluster

Function Disconnect-WMCluster {
    <#
        .SYNOPSIS
        Add a Prefix List to an NSX-T Route Map

        .DESCRIPTION
        The Add-NsxtPrefixList cmdlet adds a refix List to an NSX-T Route Map

        .EXAMPLE
        Get-NsxtPrefixList -Name sfo-w01-cl01-prefix-list | Add-NsxtPrefixList -RouteMap sfo-w01-ec01-route-map -Action PERMIT
        This example creates a new Prefix List on a Tier 0 Gateway
    #>

    Try {
        Invoke-Expression "kubectl vsphere logout"
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Disconnect-WMCluster

Function New-TanzuKubernetesCluster {
    <#
        .SYNOPSIS
        Adds a Tanzu Kubernetes cluster based on the specified YAML file.

        .DESCRIPTION
        The New-WMTkgsCluster cmdlet adds a Tanzu Kubernetes cluster based on the specified YAML file.

        .EXAMPLE
        New-WMTkgsCluster -YAML c:\kube\yaml\tkgsCluster.yaml
        This example creates a new Prefix List on a Tier 0 Gateway
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$YAML
    )

    Try {
        Invoke-Expression "kubectl apply -f $YAML"
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
New-Alias -name Set-TanzuKubernetesCluster -Value Mew-TanzuKubernetesCluster
Export-ModuleMember -Alias Set-TanzuKubernetesCluster -Function New-TanzuKubernetesCluster

Function Get-TanzuKubernetesCluster {
    <#
        .SYNOPSIS
        Retrieves a Tanzu Kubernetes cluster

        .DESCRIPTION
        The Get-TanzuKuberntesCluster cmdlet retrieves a Tanzu Kubernetes cluster

        .EXAMPLE
        Get-TanzuKubernetesCluster
        This example retrieves all TanzuKubernetesCluster objects from all namespaces

        .EXAMPLE
        Get-TanzuKubernetesCluster -Name sfo-w01-tkc01 -Namespace sfo-w01-tkc01
        This example retrieves a TanzuKubernetesCluster object named "sfo-w01-tkc01" from the namespace specified "sfo-w01-tkc01"
    #>

    Param (
        [Parameter (Mandatory = $false)] [String]$Name,
        [Parameter (Mandatory = $false)] [String]$Namespace,
        [Parameter (Mandatory = $false)] [Bool]$Detailed
    )

    if ($Detailed -eq $true) {
        if (!$Name -and !$Namespace) {
            Invoke-Expression "kubectl describe tkc --all-namespaces"
        }
        elseif (!$Name -and $Namespace) {
            Invoke-Expression "kubectl describe tkc -n $Namespace"
        }
        elseif ($Name -and !$Namespace) {
            Write-Error "A resource cannot be retrieved by name across all namespaces"
        }
        elseif ($Name -and $Namespace) {
            Invoke-Expression "kubectl describe tkc $Name -n $Namespace"
        }
    }
    elseif (!$Detailed -or $Detailed -eq $false) {
        if (!$Name -and !$Namespace) {
            Invoke-Expression "kubectl get tkc --all-namespaces"
        }
        elseif (!$Name -and $Namespace) {
            Invoke-Expression "kubectl get tkc -n $Namespace"
        }
        elseif ($Name -and !$Namespace) {
            Write-Error "A resource cannot be retrieved by name across all namespaces"
        }
        elseif ($Name -and $Namespace) {
            Invoke-Expression "kubectl get tkc $Name -n $Namespace"
        }
    }
}
Export-ModuleMember -Function Get-TanzuKubernetesCluster

Function Remove-TanzuKubernetesCluster {
    <#
        .SYNOPSIS
        Adds a Tanzu Kubernetes cluster based on the specified YAML file.

        .DESCRIPTION
        The New-WMTkgsCluster cmdlet adds a Tanzu Kubernetes cluster based on the specified YAML file.

        .EXAMPLE
        New-WMTkgsCluster -YAML c:\kube\yaml\tkgsCluster.yaml
        This example creates a new Prefix List on a Tier 0 Gateway
    #>

    Param (
        [Parameter (Mandatory = $true)] [String]$Name,
        [Parameter (Mandatory = $true)] [String]$Namespace
    )

    Try {
        Invoke-Expression "kubectl delete tkc $Name -n $Namespace"
    }
    Catch {
        Write-Error "Something went wrong."
    }
}
Export-ModuleMember -Function Remove-TanzuKubernetesCluster

#############  End vSphere with Tanzu Functions ###############
###############################################################


########################################################################################
##################  Start vRealize Suite Lifecycle Manager Functions ###################

Function Request-vRSLCMToken {
    <#
        .SYNOPSIS
        Connects to the specified vRealize Suite Lifecycle Manager and obtains authorization token

        .DESCRIPTION
        The Request-vRSLCMToken cmdlet connects to the specified vRealize Suite Lifecycle Manager and
        obtains an authorization token. It is required once per session before running all other cmdlets.

        .EXAMPLE
        Request-vRSLCMToken -fqdn xreg-vrslcm.rainpole.io -username admin@local -password VMware1!
        This example shows how to connect to the vRealize Suite Lifecycle Manager appliance
      #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$password
    )

    if ( -not $PsBoundParameters.ContainsKey("username") -or ( -not $PsBoundParameters.ContainsKey("password"))) {
        $creds = Get-Credential # Request Credentials
        $username = $creds.UserName.ToString()
        $password = $creds.GetNetworkCredential().password
    }

    $Global:vrslcmHeaders = createBasicAuthHeader $username $password
    $Global:vrslcmAppliance = $fqdn

    Try {
        # Validate credentials by executing an API call
        $uri = "https://$vrslcmAppliance/lcmversion"
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vrslcmHeaders -SkipCertificateCheck # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
        }
        else {
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vrslcmHeaders
        }
        if ($response.StatusCode -eq 200) {
            Write-Output "Successfully connected to the vRealize Suite Lifecycle Manager Appliance: $vrslcmAppliance"
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Request-vRSLCMToken

Function Get-vRSLCMLockerPassword {
    <#
        .SYNOPSIS
        Get paginated list of Passwords available in the Store

        .DESCRIPTION
        The Get-vRSLCMLockerPassword cmdlet gets a paginated list of passwords available in the Locker

        .EXAMPLE
        Get-vRSLCMLockerPassword
        This example gets all passwords in the Locker

        .EXAMPLE
        Get-vRSLCMLockerPassword -vmid 83abd0fd-c92d-4d8f-a5e8-9a1fc4fa6009
        This example gets the details of a password based on the vmid
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$vmid
    )

    Try {
        if ($PsBoundParameters.ContainsKey("vmid")) {
            $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords/$vmid"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
            $response
        }
        else {
            $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
            $response.passwords
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-vRSLCMLockerPassword

Function Add-vRSLCMLockerPassword {
    <#
        .SYNOPSIS
        Creates a new Password in a Locker

        .DESCRIPTION
        The Add-vRSLCMLockerPassword cmdlet add as new passwords to the Locker

        .EXAMPLE
        Add-vRSLCMLockerPassword -userName admin -alias xint-admin -password VMw@re1! -description "Password for Cross-Instance Admin"
        This example adda a password to the locker
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$userName,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$alias,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$description
    )

    Try {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords"

        if ($PsBoundParameters.ContainsKey("description")) {
            $body = '{
                "alias": "'+ $alias +'",
                "password": "'+ $password +'",
                "passwordDescription": "'+ $description +'",
                "userName": "'+ $userName +'"
            }'
        }
        else {
            $body = '{
                "alias": "'+ $alias +'",
                "password": "'+ $password +'",
                "userName": "'+ $userName +'"
            }'           
        }

        $response = Invoke-RestMethod $uri -Method 'POST' -Headers $vrslcmHeaders -Body $body
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Add-vRSLCMLockerPassword

Function Remove-vRSLCMLockerPassword {
    <#
        .SYNOPSIS
        Delete a Password based on vmid

        .DESCRIPTION
        The Remove-vRSLCMLockerPassword cmdlet deletes a password from the Locker

        .EXAMPLE
        Remove-vRSLCMLockerPassword -vmid
        This example delets the password with the vmid
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vmid
    )

    Try {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords/$vmid"
        $response = Invoke-RestMethod $uri -Method 'DELETE' -Headers $vrslcmHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Remove-vRSLCMLockerPassword

Function Get-vRSLCMLockerCertificate {
    <#
        .SYNOPSIS
        Get paginated list of Certificates available in the Store

        .DESCRIPTION
        The Get-vRSLCMLockerCertificate cmdlet gets a paginated list of certificates available in the Locker

        .EXAMPLE
        Get-vRSLCMLockerCertificate
        This example gets all certificates in the Locker

        .EXAMPLE
        Get-vRSLCMLockerCertificate -vmid 83abd0fd-c92d-4d8f-a5e8-9a1fc4fa6009
        This example gets the details of a certificate based on the vmid

        .EXAMPLE
        Get-vRSLCMLockerCertificate -alias xint-vrops01
        This example gets the details of a certificate based on the vmid
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$vmid,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$alias
    )

    Try {
        if ($PsBoundParameters.ContainsKey("vmid")) {
            $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/certificates/$vmid"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
            $response
        }
        elseif ($PsBoundParameters.ContainsKey("alias")) {
            $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/certificates"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
            $response.certificates | Where-Object {$_.alias -eq $alias}
        }
        else {
            $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/certificates"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
            $response.certificates
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-vRSLCMLockerCertificate

Function Add-vRSLCMLockerCertificate {
    <#
        .SYNOPSIS
        Add a certificate to the vRSLCM locker

        .DESCRIPTION
        The Add-vRSLCMLockerCertificate cmdlet adds a certificate to the vRSLCM locker

        .EXAMPLE
        Add-vRSLCMLockerCertificate
        This example gets all certificates in the Locker

        .EXAMPLE
        Add-vRSLCMLockerCertificate -vmid 83abd0fd-c92d-4d8f-a5e8-9a1fc4fa6009
        This example gets the details of a certificate based on the vmid
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vrslcmFQDN,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$certificateAlias,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$certificatePassphrase,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$certChainPath
    )

    Try {
        $newPEMString
        foreach ($line in Get-Content $certChainPath) {
            $stringToAdd = $line + '\n'
            $newPEMString += $stringToAdd
        }
    $chain = [regex]::split($newPEMString, "-----BEGIN RSA PRIVATE KEY-----")[0] -replace ".{2}$"
    $key = [regex]::split($newPEMString, "-----END CERTIFICATE-----")[-1].substring(2)
    if (!$PsBoundParameters.ContainsKey("certificatePassphrase")) {
        $body = '{
            "alias": "'+$certificateAlias+'",
            "certificateChain": "'+$chain+'",
            "privateKey": "'+$key+'"
        }'
    }
    else {
        $body = '{
            "alias": "'+$certificateAlias+'",
            "certificateChain": "'+$chain+'",
            "certificatePassphrase": "'+$certificatePassphrase+'",
            "privateKey": "'+$key+'"
        }'
        }

        $uri = "https://$vrslcmFQDN/lcm/locker/api/v2/certificates/import"
        $response = Invoke-RestMethod $uri -Method 'POST' -Headers $vrslcmHeaders -ContentType application/json -body $body
        $response.certInfo
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}

Export-ModuleMember -Function Add-vRSLCMLockerCertificate

Function Remove-vRSLCMLockerCertificate {
    <#
        .SYNOPSIS
        Delete a certificate based on vmid

        .DESCRIPTION
        The Remove-vRSLCMLockerCertificate cmdlet deletes a certificate from the Locker

        .EXAMPLE
        Remove-vRSLCMLockerCertificate -vmid
        This example delets the certificate with the vmid
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vmid
    )

    Try {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/certificates/$vmid"
        $response = Invoke-RestMethod $uri -Method 'DELETE' -Headers $vrslcmHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Remove-vRSLCMLockerCertificate

Function Get-vRSLCMLockerLicense {
    <#
        .SYNOPSIS
        Get paginated list of License available in the Store

        .DESCRIPTION
        The Get-vRSLCMLockerPassword cmdlet gets a paginated list of license available in the Locker

        .EXAMPLE
        Get-vRSLCMLockerLicense
        This example gets all license in the Locker

        .EXAMPLE
        Get-vRSLCMLockerLicense -vmid 2b54b028-9eba-4d2f-b6ee-66428ea2b297
        This example gets the details of a license based on the vmid

        .EXAMPLE
        Get-vRSLCMLockerLicense -alias "vRealize Operations Manager"
        This example gets the details of a license based on the alias name
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$vmid,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$alias
    )

    Try {
        if ($PsBoundParameters.ContainsKey("vmid")) {
            $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/licenses/detail/$vmid"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
            $response
        }
        elseif ($PsBoundParameters.ContainsKey("alias")) {
            $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/licenses/alias/$alias"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
            $response
        }
        else {
            $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/licenses"
            $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
            $response
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-vRSLCMLockerLicense

Function Add-vRSLCMLockerLicense {
    <#
        .SYNOPSIS
        Creates a new License in a Locker

        .DESCRIPTION
        The Add-vRSLCMLockerLicense cmdlet adds as new license to the Locker

        .EXAMPLE
        Add-vRSLCMLockerLicense -alias "vRealise Operations Manager" -license "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
        This example adds a license to the Locker
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$alias,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$license
    )

    Try {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/license/validate-and-add"
        $body = '{
            "alias": "'+ $alias +'",
            "serialKey": "'+ $license +'"
        }'           

        $response = Invoke-RestMethod $uri -Method 'POST' -Headers $vrslcmHeaders -Body $body
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Add-vRSLCMLockerLicense

Function Remove-vRSLCMLockerLicense {
    <#
        .SYNOPSIS
        Delete a License based on vmid

        .DESCRIPTION
        The Remove-vRSLCMLockerLicense cmdlet deletes a license from the Locker

        .EXAMPLE
        Remove-vRSLCMLockerLicense -vmid
        This example delets the license with the vmid
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vmid
    )

    Try {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/licenses/$vmid"
        $response = Invoke-RestMethod $uri -Method 'DELETE' -Headers $vrslcmHeaders
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Remove-vRSLCMLockerLicense

###################  End vRealize Suite Lifecycle Manager Functions ####################
########################################################################################


################################################################
############  Start vRealize Automation Functions  #############

Function Request-vRAToken {
    <#
        .SYNOPSIS
        Connects to the specified vRealize Automation and obtains authorization token

        .DESCRIPTION
        The Request-vRAToken cmdlet connects to the specified vRealize Automation and obtains an authorization token.
        It is required once per session before running all other cmdlets.

        .EXAMPLE
        Request-vRAToken -fqdn xreg-vra01.rainpole.io -username configadmin -password VMware1!
        This example shows how to connect to the vRealize Automation appliance

        .EXAMPLE
        Request-vRAToken -fqdn xreg-vra01.rainpole.io -username configadmin -password VMware1! -displayToken
        This example shows how to connect to the vRealize Automation appliance and display the token needed for Terraform
      #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$password,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$tenant,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$displayToken
    )

    if ( -not $PsBoundParameters.ContainsKey("username") -or ( -not $PsBoundParameters.ContainsKey("password"))) {
        $creds = Get-Credential # Request Credentials
        $username = $creds.UserName.ToString()
        $password = $creds.GetNetworkCredential().password
    }

    $Global:vraHeaders = createBasicAuthHeader $username $password
    $Global:vraAppliance = $fqdn

    Try {
        # Validate credentials by executing an API call
        $uri = "https://$vraAppliance/csp/gateway/am/api/login?access_token"
        if ($PsBoundParameters.ContainsKey("tenant")) {
            $body = "{ ""username"":""$username"",""password"":""$password"",""domain"":""$tenant""}"
        }
        else {
            $body = "{ ""username"":""$username"",""password"":""$password""}"
        }

        if ($PSEdition -eq 'Core') {
            $Global:response = Invoke-WebRequest -Method POST -Uri $uri -Headers $vraHeaders -Body $body -SkipCertificateCheck # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
        }
        else {
            $Global:response = Invoke-WebRequest -Method POST -Uri $uri -Headers $vraHeaders -Body $body
        }

        if ($response.StatusCode -eq 200) {
            Write-Output "Successfully connected to vRealize Automation: $vraAppliance"
            if ($PsBoundParameters.ContainsKey("displayToken")) {
                Write-Output "`n---------Refresh Token---------"
                ((Select-String -InputObject $response -Pattern '"refresh_token":') -Split ('"'))[3]
                Write-Output "-------------------------------`n"
            }
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Request-vRAToken

############  End vRealize Automation Functions  #############
################################################################

##########################################  E N D   O F   F U N C T I O N S  ##########################################
#######################################################################################################################


###############################################################
##################  Start Utility Functions ###################

Function Debug-ExceptionWriter {
    Param (
        [Parameter(Mandatory = $true)]
        [PSObject]$object
    )

    $lineNumber = $object.InvocationInfo.ScriptLineNumber
    $lineText = $object.InvocationInfo.Line.trim()
    $errorMessage = $object.Exception.Message
    Write-Output " Error at Script Line $lineNumber"
    Write-Output " Relevant Command: $lineText"
    Write-Output " Error Message: $errorMessage"
}
Export-ModuleMember -Function Debug-ExceptionWriter

Function Get-ExternalFileName ($title, $fileType, $location)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.Title = "$title"
    if ($location -eq "default") {
        $OpenFileDialog.initialDirectory = Get-Location
    }
    else {
        $OpenFileDialog.initialDirectory = $location
    }
    $OpenFileDialog.filter = "All files (*.$fileType) | *.$fileType"
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filename
}

Function Get-ExternalDirectoryPath {
    Add-Type -AssemblyName System.Windows.Forms
    $directory = New-Object System.Windows.Forms.FolderBrowserDialog
    $null = $directory.ShowDialog()
    $directoryPath = $directory.SelectedPath
    $directoryPath
}


Function cidrMaskLookup {
    Param (
        [Parameter (Mandatory = $true)][ValidateSet("mask", "cidr")] [String]$source,  
        [Parameter (Mandatory = $true)] [String]$value
    )

    $subnetMasks = @(
        ($32 = @{ cidr = "32"; mask = "255.255.255.255" }),
        ($31 = @{ cidr = "31"; mask = "255.255.255.254" }),
        ($30 = @{ cidr = "30"; mask = "255.255.255.252" }),
        ($29 = @{ cidr = "29"; mask = "255.255.255.248" }),
        ($28 = @{ cidr = "28"; mask = "255.255.255.240" }),
        ($27 = @{ cidr = "27"; mask = "255.255.255.224" }),
        ($26 = @{ cidr = "26"; mask = "255.255.255.192" }),
        ($25 = @{ cidr = "25"; mask = "255.255.255.128" }),
        ($24 = @{ cidr = "24"; mask = "255.255.255.0" }),
        ($23 = @{ cidr = "23"; mask = "255.255.254.0" }),
        ($22 = @{ cidr = "22"; mask = "255.255.252.0" }),
        ($21 = @{ cidr = "21"; mask = "255.255.248.0" }),
        ($20 = @{ cidr = "20"; mask = "255.255.240.0" }),
        ($19 = @{ cidr = "19"; mask = "255.255.224.0" }),
        ($18 = @{ cidr = "18"; mask = "255.255.192.0" }),
        ($17 = @{ cidr = "17"; mask = "255.255.128.0" }),
        ($16 = @{ cidr = "16"; mask = "255.255.0.0" }),
        ($15 = @{ cidr = "15"; mask = "255.254.0.0" }),
        ($14 = @{ cidr = "14"; mask = "255.252.0.0" }),
        ($13 = @{ cidr = "13"; mask = "255.248.0.0" }),
        ($12 = @{ cidr = "12"; mask = "255.240.0.0" }),
        ($11 = @{ cidr = "11"; mask = "255.224.0.0" }),
        ($10 = @{ cidr = "10"; mask = "255.192.0.0" }),
        ($9 = @{ cidr = "9"; mask = "255.128.0.0" }),
        ($8 = @{ cidr = "8"; mask = "255.0.0.0" }),
        ($7 = @{ cidr = "7"; mask = "254.0.0.0" }),
        ($6 = @{ cidr = "6"; mask = "252.0.0.0" }),
        ($5 = @{ cidr = "5"; mask = "248.0.0.0" }),
        ($4 = @{ cidr = "4"; mask = "240.0.0.0" }),
        ($3 = @{ cidr = "3"; mask = "224.0.0.0" }),
        ($2 = @{ cidr = "2"; mask = "192.0.0.0" }),
        ($1 = @{ cidr = "1"; mask = "128.0.0.0" }),
        ($0 = @{ cidr = "0"; mask = "0.0.0.0" })			
    )
    If ($source -eq "Mask")
    {
        $found = $subnetMasks | Where-Object { $_.'mask' -eq $value }
        $returnValue = $found.cidr
    }
    else
    {
        $found = $subnetMasks | Where-Object { $_.'cidr' -eq $value }
        $returnValue = $found.mask
    }   
    Return $returnValue
}

###################  End Utility Functions ####################
###############################################################

Function checkVCFToken {
    if (!$accessToken) {
        Write-Error "API Access Token Required. Request an Access Token by running Request-VCFToken"
        Break
    }
    else {
        $expiryDetails = Get-JWTDetail $accessToken
        if ($expiryDetails.timeToExpiry.Hours -eq 0 -and $expiryDetails.timeToExpiry.Minutes -lt 2) {
       	    Write-Output "API Access Token Expired. Requesting a new access token with current refresh token"
            $headers = @{"Accept" = "application/json" }
            $uri = "https://$sddcManager/v1/tokens/access-token/refresh"
            $response = Invoke-RestMethod -Method PATCH -Uri $uri -Headers $headers -body $refreshToken
            $Global:accessToken = $response
        }
    }
} Export-ModuleMember -Function checkVCFToken

Function Get-JWTDetail {
    [cmdletbinding()]

    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [string]$token
    )

    <#
        .SYNOPSIS
        Decode a JWT Access Token and convert to a PowerShell Object.
        JWT Access Token updated to include the JWT Signature (sig), JWT Token Expiry (expiryDateTime) and JWT Token time to expiry (timeToExpiry).
        Written by Darren Robinson
        https://blog.darrenjrobinson.com
        https://blog.darrenjrobinson.com/jwtdetails-powershell-module-for-decoding-jwt-access-tokens-with-readable-token-expiry-time/
        .DESCRIPTION
        Decode a JWT Access Token and convert to a PowerShell Object.
        JWT Access Token updated to include the JWT Signature (sig), JWT Token Expiry (expiryDateTime) and JWT Token time to expiry (timeToExpiry).
        .PARAMETER token
        The JWT Access Token to decode and udpate with expiry time and time to expiry
        .INPUTS
        Token from Pipeline
        .OUTPUTS
        PowerShell Object
        .SYNTAX
        Get-JWTDetail (accesstoken)
        .EXAMPLE
        PS> Get-JWTDetail ('eyJ0eXAiOi........XmN4GnWQAw7OwMA')
    #>


    if (!$token.Contains(".") -or !$token.StartsWith("eyJ")) { Write-Error "Invalid token" -ErrorAction Stop }

    # Token
    Foreach ($i in 0..1) {
        $data = $token.Split('.')[$i].Replace('-', '+').Replace('_', '/')
        Switch ($data.Length % 4) {
            0 { break }
            2 { $data += '==' }
            3 { $data += '=' }
        }
    }

    $decodedToken = [System.Text.Encoding]::UTF8.GetString([convert]::FromBase64String($data)) | ConvertFrom-Json
    Write-Verbose "JWT Token:"
    Write-Verbose $decodedToken

    # Signature
    Foreach ($i in 0..2) {
        $sig = $token.Split('.')[$i].Replace('-', '+').Replace('_', '/')
        Switch ($sig.Length % 4) {
            0 { break }
            2 { $sig += '==' }
            3 { $sig += '=' }
        }
    }
    Write-Verbose "JWT Signature:"
    Write-Verbose $sig
    $decodedToken | Add-Member -Type NoteProperty -Name "sig" -Value $sig

    # Convert Expiry time to PowerShell DateTime
    $orig = (Get-Date -Year 1970 -Month 1 -Day 1 -hour 0 -Minute 0 -Second 0 -Millisecond 0)
    $timeZone = Get-TimeZone
    $utcTime = $orig.AddSeconds($decodedToken.exp)
    $hoursOffset = $timeZone.GetUtcOffset($(Get-Date)).hours #Daylight saving needs to be calculated
    $localTime = $utcTime.AddHours($hoursOffset)     # Return local time,
    $decodedToken | Add-Member -Type NoteProperty -Name "expiryDateTime" -Value $localTime

    # Time to Expiry
    $timeToExpiry = ($localTime - (get-date))
    $decodedToken | Add-Member -Type NoteProperty -Name "timeToExpiry" -Value $timeToExpiry

    Return $decodedToken
} Export-ModuleMember -Function Get-JWTDetail

Function createHeader {
    $Global:headers = @{"Accept" = "application/json" }
    $Global:headers.Add("Authorization", "Bearer $accessToken")
}

Function createBasicAuthHeader {
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password))) # Create Basic Authentication Encoded Credentials
    $headers = @{"Accept" = "application/json" }
    $headers.Add("Authorization", "Basic $base64AuthInfo")
    $headers.Add("Content-Type", "application/json")
    $headers
}

Function createvCenterAuthHeader {
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password)))
    $vcAuthHeaders = @{"vmware-use-header-authn" = "true" }
    $vcAuthHeaders.Add("Authorization", "Basic $base64AuthInfo")
    $vcAuthHeaders
}

Function createVAMIAuthHeader {
    $VAMIAuthheaders = @{"Content-Type" = "application/json" }
    $VAMIAuthheaders.Add("dr.config.service.sessionid", "$sessionId")
    $VAMIAuthheaders
}

Function Request-VAMISessionId
{
    <#
		.SYNOPSIS
    	Connects to the specified VAMI interface and requests a session token

    	.DESCRIPTION
    	The Request-VAMISessionId cmdlet connects to the specified VAMI interface and requests a session token.
    	It is required once per session before running all other cmdlets

    	.EXAMPLE
    	PS C:\> Request-VAMISessionId -fqdn sfo-vcf01.sfo.rainpole.io -username root -password VMw@re1!
        This example shows how to connect to a VAMI interface to request a session token
  	#>

  	Param (
    	[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [string]$fqdn,
		[Parameter (Mandatory=$false)] [ValidateNotNullOrEmpty()] [string]$username,
		[Parameter (Mandatory=$false)] [ValidateNotNullOrEmpty()] [string]$password
  	)

  	If ( -not $PsBoundParameters.ContainsKey("username") -or ( -not $PsBoundParameters.ContainsKey("password"))) {
   		# Request Credentials
    	$creds = Get-Credential
    	$username = $creds.UserName.ToString()
    	$password = $creds.GetNetworkCredential().password
    }


  	    # Validate credentials by executing an API call
  	    $headers = @{"Content-Type" = "application/json"}
  	    $uri = "https://"+$fqdn+":5480/configure/requestHandlers/login"
  	    $body = '{"username": "'+$username+'","password": "'+$password+'"}'

  	    Try {
    	    # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
    	    if ($PSEdition -eq 'Core') {
      	    	$response = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -body $body -SkipCertificateCheck
      	    	$sessionId = $response.data.sessionId
    	    }
    	    else {
      		    $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -body $body
      		    $Global:sessionId = $response.data.sessionId
               
    	    }
    	    if ($response.data.sessionId) {
                #Write-Output "Successfully Requested New VAMI Session Token From: $fqdn"
                $sessionId
    	    }
  	    }
  	    Catch {
            Write-Error $_.Exception.Message
        }
    }
Export-ModuleMember -Function Request-VAMISessionId

########################################################################
#####################  Start of Unused Functions  ######################

Function Join-ESXiActiveDirectory {
    # Join each ESXi Host to the Active Directory Domain
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainJoinUser,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainJoinPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vcfDomain
    )

    Try {
        $vcenter = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $vcfDomain
        Connect-VIServer -Server $vcenter.fqdn -User $vcenter.ssoAdmin -pass $vcenter.ssoAdminPass | Out-Null
        if ($DefaultVIServer.Name -eq $($vcenter.fqdn)) {
            $checkAdAuthentication = Test-ADAuthentication -user $domainJoinUser -pass $domainJoinPass -server $domain -domain $domain
            if ($checkAdAuthentication -contains "2") {
                $esxiHosts = Get-VMHost
                $count = 0
                Foreach ($esxiHost in $esxiHosts) {
                    $currentDomainState = Get-VMHostAuthentication -VMHost $esxiHost
                    $currentDomain = [String]$currentDomainState.Domain
                    if ($currentDomain -ne $domain) {
                        Get-VMHostAuthentication -VMHost $esxiHost | Set-VMHostAuthentication -Domain $domain -JoinDomain -Username $domainJoinUser -Password $domainJoinPass -Confirm:$false | Out-Null
                        $currentDomainState = Get-VMHostAuthentication -VMHost $esxiHost
                        $currentDomain = [String]$currentDomainState.Domain
                        if ($currentDomain -eq $domain.ToUpper()) {
                            Write-Output "Confirmed ESXi Host $esxiHost joined Active Directory Domain $domain Successfully"
                        }
                        else {
                            Write-Error "Adding ESXi Host $esxiHost to Active Directory Domain $domain Failed"
                        }
                    }
                    else {
                        Write-Warning "ESXi Host $esxiHost already joined to Active Directory Domain $domain"
                    }
                    $count = $count + 1
                }
            }
            else {
                Write-Error "Domain User $domainJoinUser Authentication Failed"
            }
        }
        else {
            Write-Error  "Not connected to vCenter Server $($vcenter.fqdn)"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Join-ESXiActiveDirectory

Function Add-ESXiDomainUser {
    # Assign an Active Directory Group to each ESXi Host for Administration
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainBindUser,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainBindPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$principal,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$role,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [bool]$propagate,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vcfDomain
    )

    $securePass = ConvertTo-SecureString -String $domainBindPass -AsPlainText -Force
    $domainCreds = New-Object System.Management.Automation.PSCredential ($domainBindUser, $securePass)
    $addPrincipal = ($domain.Split(".")[0]).ToUpper() + "\" + $principal

    Try {
        Request-VCFToken -fqdn $server -Username $user -Password $pass | Out-Null
        if ($accessToken) {
            $esxiHosts = (Get-VCFCredential | Where-Object { $_.resource.domainName -eq $vcfDomain -and $_.accountType -eq "USER" -and $_.resource.resourceType -eq "ESXI" }).resource.resourceName
            if (Get-ADGroup -Server $domain -Credential $domainCreds -Filter { SamAccountName -eq $principal }) {
                $count = 0
                Foreach ($esxiHost in $esxiHosts) {
                    $esxiCreds = Get-VCFCredential | Where-Object { $_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER" }
                    Connect-VIServer -Server $esxihost -User $esxiCreds.username -Pass $esxiCreds.password | Out-Null # Connect to ESXi Server
                    if ($DefaultVIServer.Name -eq $esxihost) {
                        $checkPermission = Get-VIPermission | Where-Object { $_.Principal -eq $addPrincipal }
                        if ($checkPermission.Principal -eq $addPrincipal) {
                            Write-Warning "Active Directory Group '$addPrincipal' already assigned permissions to $esxihost"
                        }
                        else {
                            New-VIPermission -Entity $esxiHost -Principal $addPrincipal -Propagate $propagate -Role $role
                            $checkPermission = Get-VIPermission | Where-Object { $_.Principal -eq $addPrincipal }
                            if ($checkPermission.Principal -eq $addPrincipal) {
                                Write-Output "Active Directory Group '$addPrincipal' assigned the Administrator role to $esxihost Successfully"
                            }
                            else {
                                Write-Error "Assigning Active Directory Group '$addPrincipal' the Administrator role to $esxihost Failed"
                            }
                        }
                        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue # Disconnect from ESXi Server
                        $count = $count + 1
                    }
                    else {
                        Write-Error "Failed to connect to ESXi host $esxihost"
                        $count = $count + 1
                    }
                }
            }
            else {
                Write-Error "Active Directory User/Group '$addPrincipal' not found in the Active Directory Domain, please create and retry"
            }
        }
        else {
            Write-Error "Failed to obtain access token from SDDC Manager, check details provided"
        }
    }
    Catch {
        Debug-ExceptionWriter -object $_
    }
}
Export-ModuleMember -Function Add-ESXiDomainUser

#######################  End Unused Functions  #########################
########################################################################