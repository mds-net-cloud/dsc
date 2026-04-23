$GlobalConfig = @{

    # ========================
    # Identität / Netzwerk
    # ========================
    Node = @{
        Name        = "pcktst1dsc"
        DomainName  = "test.auf.xxx.de"
        Description = "DSC TestServer"
        IP          = "184.6.79.233"

        NetworkingDsc = "PCK.Test-Server"

        DnsServers  = @("184.6.79.193", "184.6.79.194")

        DomainJoin = @{
            Username = "svcpt1domjoin@auf.xxx.de"
            Password = "xxx"
        }
    }

    # ========================
    # OpenStack
    # ========================
    OpenStack = @{
        Image   = "Windows Server 2022 Core 241202"
        Flavor  = "gp-g1-l"

        Volumes = @(
            @{ Name = "OS";   Size = 80; Letter = "C" }
            @{ Name = "Data"; Size = 40; Letter = "F" }
        )
    }

    # ========================
    # Pfade
    # ========================
    Paths = @{
        DscRoot   = "C:\DSC"
        Temp      = "C:\Temp"
        Logs      = "C:\DSC\logs"
    }
}
