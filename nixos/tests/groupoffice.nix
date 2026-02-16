{ lib, ... }:

{
  name = "groupoffice";
  meta.maintainers = with lib.maintainers; [ ThyMYthOS ];

  nodes = {
    declarative = {
      services.groupoffice = {
        enable = true;
        setupMode = "declarative";
        database.createLocally = true;
        settings = {
          checkForUpdates = false;
          nav_page_size = 123;
        };
        virtualHost = {
          hostName = "localhost";
          forceSSL = false;
          enableACME = false;
        };
      };
    };

    installer = {
      services.groupoffice = {
        enable = true;
        setupMode = "web-installer";
        database.createLocally = true;
        virtualHost = {
          hostName = "localhost";
          forceSSL = false;
          enableACME = false;
        };
      };
    };
  };

  testScript = ''
    start_all()

    for machine in (declarative, installer):
      machine.wait_for_unit("mysql.service")
      machine.wait_until_succeeds(
        "test \"$(systemctl show -P Result groupoffice-setup.service)\" = \"success\""
      )
      machine.wait_for_unit("phpfpm-groupoffice.service")
      machine.wait_for_unit("httpd.service")
      machine.wait_for_open_port(80)
      machine.succeed("curl -fL http://localhost/install/index.php")

    declarative.succeed("grep -F \"db_name\" /var/lib/groupoffice/config.php | grep -F \"groupoffice\"")
    declarative.succeed("grep -F \"checkForUpdates\" /var/lib/groupoffice/config.php | grep -F \"false\"")
    declarative.succeed("grep -F \"nav_page_size\" /var/lib/groupoffice/config.php | grep -F \"123\"")
    declarative.succeed("readlink /etc/groupoffice/config.php | grep -F /var/lib/groupoffice/config.php")
    installer.succeed("test -w /var/lib/groupoffice/config.php")
  '';
}
