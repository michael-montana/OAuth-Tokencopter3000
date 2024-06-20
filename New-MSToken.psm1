<#
.SYNOPSIS
This function generates a new OAuth token.

.DESCRIPTION
The function takes in parameters such as ClientId, ClientSecret, RefreshToken, TokenIssuerURL, Resource, AccessToken, and AppInsParentActivity. It validates these parameters and generates a new OAuth token.

.PARAMETER ClientId
The client ID of the Entra ID application.

.PARAMETER ClientSecret
The client secret of the Entra ID application.

.PARAMETER RefreshToken
The refresh token to use when requesting a new access token.

.PARAMETER TokenIssuerURL
The token issuer URL of the Entra ID application.

.PARAMETER Resource
The resource to access. This is the URL of the resource for which the access token is required.

.PARAMETER AccessToken
Current access token to verify if expired. If yes > new Access Token will requested. If no > it will be returned.

.PARAMETER AppInsParentActivity
Application Insights Telemetry.

.EXAMPLE
New-MSToken -ClientId 'your-client-id' -ClientSecret 'your-client-secret' -RefreshToken 'your-refresh-token' -TokenIssuerURL 'https://login.microsoftonline.com/common/oauth2/token' -Resource 'https://graph.microsoft.com' -AccessToken 'your-access-token'

.NOTES
Author: Michael Montana
Email: michael_montana@outlook.com
#>
function New-MSToken() {
    param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "The client ID of the Entra ID application.")]
        [ValidateScript({
                if ($_ -match '(?im)[0-9A-F]{8}[-](?:[0-9A-F]{4}[-]){3}[0-9A-F]{12}') {
                    $true
                }
                else {
                    throw "ClientId does not match vaild GUID (Globally Unique Identifier) format. It must only contain alphanumeric characters and hyphens. Example: 3F2504E0-4F89-11D3-9A0C-0305E82C3301"
                }
            })]
        [string]$ClientId,
          
        [Parameter(Mandatory = $true, Position = 1, HelpMessage = "The client secret of the Entra ID application.")]
        [string]$ClientSecret,
          
        [Parameter(Mandatory = $false, Position = 2, HelpMessage = "The refresh token to use when requesting a new access token.")]
        [string]$RefreshToken,
          
        [Parameter(Mandatory = $true, Position = 3, HelpMessage = "The token issuer URL of the Entra ID application. Example: https://login.microsoftonline.com/common/oauth2/token")]
        [ArgumentCompletions('https://login.microsoftonline.com/common/oauth2/token', 'https://login.microsoftonline.com/<GUID>/oauth2/token', 'https://login.microsoftonline.com/<GUID>/oauth2/v2.0/token')]
        [ValidateScript({
                if ($_ -match '^https://([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}(/.*)?$') {
                    $true
                }
                else {
                    throw "The TokenIssuerURL `$_` is not a valid HTTPS URL. One Example is: https://login.microsoftonline.com/<GUID>/oauth2/v2.0/token"
                }
            })]
        [string]$TokenIssuerURL,
  
        [Parameter(Mandatory = $true, Position = 4, HelpMessage = "The resource to access. This is the URL of the resource for which the access token is required. For example, https://graph.microsoft.com.")]
        [ArgumentCompletions('https://api.partnercenter.microsoft.com', 'https://api.partnercenter.microsoft.com/user_impersonation', 'https://graph.microsoft.com', 'https://graph.microsoft.com/.default', 'https://management.azure.com/.default')]
        [ValidateScript({
                if ($_ -match '^https://([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}(/.*)?$') {
                    $true
                }
                else {
                    throw "The resource URL `$_` is not a valid HTTPS URL. One Example is: https://api.partnercenter.microsoft.com/user_impersonation"
                }
            })]
        [string]$Resource,
  
        [Parameter(Mandatory = $false, Position = 5, HelpMessage = "Current access token to verify if expired. If yes > new Access Token will requested. If no > it will be returned.")]
        [string]$AccessToken
    )
  
      
    $returnAccessToken = $null
  
    ###############
    ##  Check if the provided access token is expired
    ###############
    $isTokenExpired = $true
    if (-Not ([string]::IsNullOrEmpty($AccessToken))) {
          
        # Extract the payload from the access token
        $tokenContent = $AccessToken.Split(".")[1]
        $tokenContent = $tokenContent.Replace('-', '+').Replace('_', '/')
        
        # Ensure the payload length is a multiple of 4 for base64 decoding
        while ($tokenContent.Length % 4 -ne 0) { 
            $tokenContent += "=" 
        }
        
        # Convert the payload from a base64 string to a byte array
        $tokenByteArray = [System.Convert]::FromBase64String($tokenContent)
        
        # Convert the byte array to a string to get a JSON string
        $tokenJsonString = [System.Text.Encoding]::ASCII.GetString($tokenByteArray)
        
        # Parse the JSON string into a PowerShell object
        $tokenObject = ConvertFrom-Json -InputObject $tokenJsonString
        
        # Get the current Unix timestamp and add 5 minutes (300 seconds) to it
        $currentUnixTimeStamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
        $expiryUnixTimeStamp = $currentUnixTimeStamp + 300
        
        # Check if the access token is expired
        if ($expiryUnixTimeStamp -gt $tokenObject.exp) {
            Write-Verbose "The access token has expired"
            $isTokenExpired = $true
        }
        else {
            Write-Verbose "The access token has not expired"
            $isTokenExpired = $false
        }

    }

    ###############
    ##  Process Token retrieval
    ###############
    if (-Not $isTokenExpired) {

        # Access Token is not empty and not expired
        Write-Host "xAccessToken not expired - Access granted: AccessToken remains valid"
        Write-Verbose "AccessToken: $AccessToken"
  
        $returnAccessToken = $AccessToken
  
    } else {
          
        # Access Token is empty or expired
        if ([string]::IsNullOrEmpty($AccessToken)) {
            Write-Host "Warning: AccessToken parameter null or empty!"
        }
        elseif ((Confirm-BAGMSAccessTokenIsExpired -AccessToken $AccessToken) -eq $true) {
            Write-Host "Warning: AccessToken is expired!"
        }
  
        # Display OAuth TokenCopter 3000
        Write-Host "~  ~  ~  ~"
        Write-Host "    🚁     -----  OAuth TokenCopter 3000 on the way to help you out!"
        Write-Host "__________"
  
        # Is there a Refreshtoken provided?
        if ([string]::IsNullOrEmpty($RefreshToken) -ne $true) {
  
            Write-Verbose "RefreshToken: $RefreshToken"
  
            # 'refresh_token' grant type selected
            $GrantType = "refresh_token"
            Write-Verbose "GrantType: $GrantType"
  
            if ($TokenIssuerURL -notlike "*v2.0*") {
                  
                # v1.0 token issuer URL detected > params must contain 'resource'
  
                $refreshTokenParams = @{
                    'grant_type'    = $GrantType
                    'client_id'     = $ClientId
                    'client_secret' = $ClientSecret
                    'refresh_token' = $RefreshToken
                    'resource'      = $Resource
                }
                Write-Verbose "refreshTokenParams: $refreshTokenParams"
  
            }
            elseif ($TokenIssuerURL -like "*v2.0*") {
  
                # v2.0 token issuer URL detected > params must contain 'scope'
  
                $refreshTokenParams = @{
                    'grant_type'    = $GrantType
                    'client_id'     = $ClientId
                    'client_secret' = $ClientSecret
                    'refresh_token' = $RefreshToken
                    'scope'         = $Resource
                }
                Write-Verbose "refreshTokenParams: $refreshTokenParams"
                  
            }
            else {
  
                Write-Host "Refreshtoken grant type selected, but TokenIssuerURL not supported"
  
            }
  
        }
        elseif ([string]::IsNullOrEmpty($RefreshToken) -eq $true) {
  
            # 'client_credentials' grant type selected > params does not allow 'refresh_token' and must contain 'scope'
            $GrantType = "client_credentials"
            Write-Verbose "GrantType: $GrantType"
  
            $refreshTokenParams = @{
                'grant_type'    = $GrantType
                'client_id'     = $ClientId
                'client_secret' = $ClientSecret
                'scope'         = $Resource
            }
            Write-Verbose "refreshTokenParams: $refreshTokenParams"
  
        }
        else {
  
            Write-Host "GrantType not supported"
  
            $returnAccessToken = $null
  
        }
  
        # Request new Access Token
        Write-Host -NoNewline "Requesting fresh AccessToken now"
        for ($i = 0; $i -lt 6; $i++) {
            Start-Sleep -Milliseconds 500 
            Write-Host -NoNewline "."
        }
  
        try {
            $headers = @{
                'Content-Type' = 'application/x-www-form-urlencoded'
            }
            $newTokenResponse = Invoke-RestMethod -Uri $TokenIssuerURL -Method "POST" -Body $refreshTokenParams -Headers $headers
  
            # Success, new Access Token received. ErrorAction Stop will catch any error and jump to catch block
            if (-not [String]::IsNullOrEmpty($newTokenResponse)) {
                Write-Host " New Access Token obtained - all clear!"
            }
        }
        catch {
  
            # Error occurred
            Write-Host " crashed!" # New line
            Write-Host "" # New line
  
            # Error handling
            throw $_
            $errorMessage = $_ | ConvertFrom-json
  
            # Extract TenantId from TokenIssuerURL
            $TokenIssuerURLParts = $TokenIssuerURL -split '/'
            $TenantId = $TokenIssuerURLParts[3]
  
            if ($errorMessage.error_description -like "*AADSTS65001*") {
  
                # Multi-Tenant App Registration does not have consent in tenant
                  
                # Prompt user to give consent
                Write-Host "Error: AADSTS65001. Multi-Tenant App Registration does not have consent in tenant $TenantId."
                Write-Host "Please login to tenant $TenantId with Global Administrator, open following URL and give consent:"
                Write-Host "https://login.microsoftonline.com/$TenantId/adminconsent?client_id=$ClientId"
  
            }
            elseif ($errorMessage.error_description -like "*AADSTS70011*") {
  
                # Invalid client secret
                Write-Host "Error: AADSTS70011. Invalid client secret."
                Write-Host "Open EntraID of Tenant $TenantId > Open App Registrations > Choose 'All applications'"
                Write-Host "Search for the App Registration $ClientId and check the client secret. If it is not correct, create a new one and replace it in the script."
  
            }
            else {
  
                Write-Host "An unexpected error occurred: $($_.Exception.Message)"
                Write-Host "Error description: $($errorMessage.error_description)"
  
            }
  
            $returnAccessToken = $null
  
        }
  
        $returnAccessToken = $newTokenResponse.access_token 
    }
  
    return $returnAccessToken
}