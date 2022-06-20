<#
.Synopsis
   PowerShell scripts to build out a training environment in Microsoft Azure for a hardening exercise
.DESCRIPTION
   https://techcommunity.microsoft.com/t5/fasttrack-for-azure/deploying-apache-guacamole-on-azure/ba-p/3269613
.EXAMPLE
#>

$resourceGroupName = "lab"
$resourceGroupLocation = "eastus"
$mysqldbName = "$resourceGroupName" + "DBinternal"
$mysqladmin = 'guacdbadminuser'
$mysqlpassword = 'MyStrongPassW0rd' #TODO figure out how to ask for input if not given as an argument
[SecureString] $securemysqlpassword = (ConvertTo-SecureString $mysqlpassword -AsPlainText -Force)
$networkName = "$resourceGroupName-vnet"
$networkPrefix = "10.0.0.0/16"
$subnetName = "$networkName-subnet"
$subnetPrefix = "10.0.1.0/24"
$availabilitySet = "$resourceGroupName-avset"
$vmadmin = 'guacuser'
$nsg = $resourceGroup + '-nsg'
$loadBalancerPIPName = "$resourceGroupName-lbpip"
$publicIPDNSName = "$resourceGroupName-" + (Get-Random)
$loadBalancerName = "$resourceGroupName-loadbalancer"
$cred = $(New-Object System.Management.Automation.PSCredential ($vmAdmin, $securemysqlpassword))
$domainName = "guacamolelab.com"
$email = "admin@guacamolelab.com"
$context

function Test-Prerequisites {
    Process {
        # Powershell 5.1 or later
        if ($PSVersionTable.PSversion.Major -lt 5 -or ($PSVersionTable.PSversion.Major -eq 5 -and $PSVersionTable.PSversion.Minor -lt 1)) {
           throw "Update to PowerShell 5.1 or later: https://docs.microsoft.com/en-us/powershell/scripting/windows-powershell/install/installing-windows-powershell#upgrading-existing-windows-powershell"
        }
        
        # Multiple Azure Modules OR Already Installed
        if ($PSVersionTable.PSEdition -eq 'Desktop' -and (Get-Module -Name AzureRM -ListAvailable)) {
             Write-Warning -Message ('Az module not installed. Having both the AzureRM and Az modules installed at the same time is not supported.')
        } else {
            if (Get-InstalledModule -Name Az) {
            } else {
                Install-Module -Name Az -AllowClobber -Scope CurrentUser
            }
        }

        # Check for Azure MySQL powershell
        # https://docs.microsoft.com/en-us/azure/mysql/single-server/quickstart-create-mysql-server-database-using-azure-powershell
 
        # Check for Context
        if (!$context) {$context = Connect-AzAccount}
       }
}

function New-AzGuacamole {
      Process {
        $startTime = Get-Date -Format "HH:mm:ss"
        Write-Host "--------------------  Beginning Initialization  ---------------------" -ForegroundColor Cyan
        Write-Host "This could take between 15-30 minutes, feel free to go top off the coffee" -ForegroundColor Cyan
        Write-Host "Script Start Time: $startTime" -ForegroundColor Cyan
        Write-Host "`n`n`n`n" -ForegroundColor Cyan     # Adding lines for the progress box

        # Create the Resource Group
        $null = New-AzResourceGroup -Name $resourceGroupName -Location $resourceGroupLocation -InformationAction SilentlyContinue

        # Create the SQL Server for Guacamole
        $null = New-AzMySQLServer -Name $mysqldbName -resourceGroupName $resourceGroupName -Location $resourceGroupLocation `
            -AdministratorUserName $mysqladmin `
            -AdministratorLoginPassword $securemysqlpassword `
            -Sku "B_Gen5_1" `
            -StorageInMb 51200 `
            -SslEnforcement "Disabled"  `
            -InformationAction SilentlyContinue #TODO: Try out Enabling SSL
        
        # Create Firewall Rule for the SQL Server
        $null = New-AzMySqlFirewallRule -ServerName $mysqldbName -ResourceGroupName $resourceGroupName `
            -Name "AllowYourIP" `
            -StartIPAddress 0.0.0.0 `
            -EndIPAddress 255.255.255.255 `
            -InformationAction SilentlyContinue #TODO: Try out smaller IP range
        
        Write-Host "Backend MYSQL database has been created" -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Cyan

        # Create a Subnet Configuration
        $subnet = New-AzVirtualNetworkSubnetConfig `
            -Name $subnetName `
            -AddressPrefix $subnetPrefix `
            -WarningAction Ignore #TODO: For loop through # of students creating same number of subnets

        # Create the Virtual Network
        $vnet = New-AzvirtualNetwork -ResourceGroupName $resourceGroupName -Location $resourceGroupLocation `
            -Name $networkName `
            -AddressPrefix $networkPrefix `
            -Subnet $subnet #TODO: Test out adding all previously created subnets from for loop

        Write-Host "Networks have been created" -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Cyan

        # Create the Availability Set for Guacamole
        $avset = New-AzAvailabilitySet -ResourceGroupName $resourceGroupName -Location $resourceGroupLocation `
            -Name $availabilitySet `
            -PlatformFaultDomainCount 2 `
            -PlatformUpdateDomainCount 3 `
            -Sku "Aligned"

        # Create the NSG Rule for HTTP Traffic
        $nsgRuleHTTP = New-AzNetworkSecurityRuleConfig `
            -Name "http-rule" `
            -Description "Allow HTTP" `
            -Access Allow `
            -Protocol Tcp `
            -Direction Inbound `
            -Priority 201 `
            -SourceAddressPrefix Internet `
            -SourcePortRange * `
            -DestinationAddressPrefix * `
            -DestinationPortRange 80

        # Create the NSG for Guacamole
        $guacNSG = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $resourceGroupLocation `
            -Name "guacamole-NSG" `
            -SecurityRules $nsgRuleHTTP

        # Create the Load balancer
        # Create the Public IP for the Loadbalancer
        $publicIP = New-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Location $resourceGroupLocation `
            -Name $loadBalancerPIPName `
            -DomainNameLabel "$($publicIPDNSName.ToLower())" `
            -AllocationMethod Static `
            -IdleTimeoutInMinutes 4 `
            -Sku Standard `
            -WarningAction Ignore
                
        # Create the frontend for the load balancer
        $frontend = New-AZLoadBalancerFrontendIPConfig -Name "Guacamole-FrontEnd" -PublicIPAddress $publicIP -WarningAction Ignore

        # Create the backend for the load balancer
        $backendAddressPool = New-AzLoadBalancerBackendAddressPoolConfig -Name "Guacamole-BackendPool"

        # Create the Health Probe for the loadbalancer HTTP
        $healthprobeHTTP = New-AZLoadBalancerProbeConfig `
            -Name "$loadBalancerName-probe-http" `
            -Protocol "http" `
            -Port 80 `
            -RequestPath "/" `
            -IntervalInSeconds 15 `
            -ProbeCount 15

        # Create Load Balancer Rule for HTTP Trafic
        $lbrule1 = New-AzLoadBalancerRuleConfig `
            -Name "loadbalancerRule-HTTP" `
            -FrontendIPConfiguration $frontend `
            -BackendAddressPool $backendAddressPool `
            -Probe $healthprobeHTTP `
            -Protocol "Tcp" `
            -FrontendPort 80 `
            -BackendPort 80 `
            -IdleTimeoutInMinutes 4 `
            -LoadDistribution SourceIPProtocol

        # Create the Load Balancer
        $loadbalancer = New-AzLoadBalancer -ResourceGroupName $resourceGroupName -Location $resourceGroupLocation `
            -Name $loadBalancerName `
            -FrontendIPConfiguration $frontend `
            -BackendAddressPool $backendAddressPool `
            -Probe $healthprobeHTTP `
            -LoadBalancingRule $lbrule1 `
            -Sku "Standard"

        Write-Host "Load balancer has been created" -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Cyan

        # Create the HA Guacamole VM's
        for ($i=1; $i -le 2; $i++){
            Write-Progress -Activity "Creating Guacamole Virtual Machines" `
                -Status "Progress:" `
                -CurrentOperation "Spinning up host #$i" `
                -PercentComplete (($i/2)*90) 

            # Create the NIC
            $NIC = New-AzNetworkInterface -ResourceGroupName $resourceGroupName -Location $resourceGroupLocation `
                -Name "guacamole-NIC-0$i" `
                -SubnetId $vnet.Subnets[0].Id `
                -NetworkSecurityGroupId $guacNSG.Id `
                -LoadBalancerBackendAddressPoolId $backendAddressPool.Id

            # Create the VM Config
            $vm = New-AzVMConfig -VMName "Guacamole-VM0$i" -VMSize "Standard_DS1_v2" -AvailabilitySetID $avset.Id

            # Set the Image
            $vm = Set-AzVMSourceImage -VM $vm `
                -PublisherName "Canonical" `
                -Offer "UbuntuServer" `
                -Skus "18.04-LTS" `
                -Version latest

            # Set OS and disable password authentication
            $vm = Set-AzVMOperatingSystem -VM $vm `
                -Linux `
                -ComputerName "Guacamole-0$i" `
                -Credential $cred

            # Add NIC to host
            $vm = Add-AzVMNetworkInterface -VM $vm -Id $NIC.Id

            # Create VM
            $null = New-AzVM -ResourceGroupName $resourceGroupName -Location $resourceGroupLocation `
                -VM $vm `
                -WarningAction Ignore `
                -InformationAction SilentlyContinue
        }
        Write-Host "Apache Guacamole hosts have been created. Configuring the instances now." -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Cyan

        # Pull down guac install script on each VM
        for ($i=1; $i -le 2; $i++){
            # Pull from GitHub repo
            $null = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName `
                -VMName "Guacamole-VM0$i" `
                -CommandId "RunShellScript" `
                -ScriptString "wget https://raw.githubusercontent.com/lbunge/CyberAcademy/main/guac-install-nossl.sh -O /tmp/guac-install.sh" `
                -InformationAction SilentlyContinue

            # Modify credentials in script
            $null = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName `
                -VMName "Guacamole-VM0$i" `
                -CommandId "RunShellScript" `
                -ScriptString "sudo sed -i.bkp -e 's/mysqlpassword/$mysqlpassword/g' \
                    -e 's/mysqldb/$mysqldbName/g' \
                    -e 's/mysqladmin/$mysqladmin/g' /tmp/guac-install.sh" `
                -InformationAction SilentlyContinue
            
            # Run the script
            $null = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName `
                -VMName "Guacamole-VM0$i" `
                -CommandId "RunShellScript" `
                -ScriptString "sudo /bin/bash /tmp/guac-install.sh" `
                -InformationAction SilentlyContinue
        }

        $endTime = Get-Date -Format "HH:mm:ss"
      }
      End {
        Write-Host "-------------------- Initialization is complete! --------------------" -ForegroundColor Cyan
        Write-Host "Script End Time: $endTime" -ForegroundColor Cyan
        Write-Host "Total Run Time: $(New-TimeSpan -Start $startTime -End $endTime)" -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Cyan
        Write-Host "To tear down all the resources once you are finished, run the following:" -ForegroundColor Cyan
        Write-Host "Remove-AzResourceGroup -Name $resourceGroupName -Force -AsJob"
        Write-Host ""
        Write-Host "To access your resources online, go to the following url:" -ForegroundColor Cyan
        Write-Host "http://$((Get-AzPublicIpAddress -name $publicIP.Name -ResourceGroupName $resourceGroupName).DnsSettings.Fqdn)"

    }

}

#TODO: Build out function to duplicate a training environment for x number of students
function New-AzStudentLabEnvironments {

}

#TODO:Install SSL into Guacamole (Saving commands here for reference)
function Install-AzGuacamoleSSL {

    # Create the Health Probe for the loadbalancer HTTPS
    $healthprobeHTTPS = New-AZLoadBalancerProbeConfig `
    -Name "$loadBalancerName-probe-https" `
    -Protocol "https" `
    -Port 443 `
    -RequestPath "/" `
    -IntervalInSeconds 15 `
    -ProbeCount 15

    # Create Load Balancer Rule for HTTPS Trafic
    $lbrule2 = New-AzLoadBalancerRuleConfig `
    -Name "loadbalancerRule-HTTPS" `
    -FrontendIPConfiguration $frontend `
    -BackendAddressPool $backendAddressPool `
    -Probe $healthprobeHTTPS `
    -Protocol "Tcp" `
    -FrontendPort 443 `
    -BackendPort 443 `
    -IdleTimeoutInMinutes 4 `
    -LoadDistribution SourceIPProtocol

    # Create the NSG Rule for HTTPS Traffic in Guacamole
    $nsgRuleHTTPS = New-AzNetworkSecurityRuleConfig `
    -Name "https-rule" `
    -Description "Allow HTTPS" `
    -Access Allow `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 301 `
    -SourceAddressPrefix Internet `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 443
}

#TODO: Function to establish new SSH credentials and open up SSH capability in NSG
function Grant-AzGuacamoleSSHCredentials {
    # NSG Rule for SSH
    $nsgRuleSSH = New-AzNetworkSecurityRuleConfig `
    -Name "SSH-rule" `
    -Description "Allow SSH" `
    -Access Allow `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 401 `
    -SourceAddressPrefix Internet `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 22
}

#TODO: Function to lock down SSH and remove keys as needed
function Revoke-AzGuacamoleSSHCredentials {

}


Test-Prerequisites
New-AzGuacamole