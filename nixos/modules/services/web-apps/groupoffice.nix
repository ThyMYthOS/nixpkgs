{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    mkPackageOption
    types
    optional
    optionalString
    ;

  cfg = config.services.groupoffice;
  fpm = config.services.phpfpm.pools.groupoffice;

  user = cfg.user;
  group = cfg.group;
  stateDir = cfg.dataDir;
  configFile = "${stateDir}/config.php";

  toPhp =
    value:
    if builtins.isBool value then
      if value then "true" else "false"
    else if value == null then
      "null"
    else if builtins.isInt value || builtins.isFloat value then
      toString value
    else if builtins.isString value then
      builtins.toJSON value
    else if builtins.isPath value then
      builtins.toJSON (toString value)
    else if builtins.isList value then
      let
        rendered = map toPhp value;
      in
      "[${optionalString (rendered != [ ]) " "}${lib.concatStringsSep ", " rendered}${
        optionalString (rendered != [ ]) " "
      }]"
    else if builtins.isAttrs value then
      let
        names = lib.attrNames value;
        rendered = map (name: "${builtins.toJSON name} => ${toPhp value.${name}}") names;
      in
      "[${optionalString (rendered != [ ]) " "}${lib.concatStringsSep ", " rendered}${
        optionalString (rendered != [ ]) " "
      }]"
    else
      throw "Unsupported GroupOffice setting value type: ${builtins.typeOf value}";

  mkConfigLine = name: value: "$config[${builtins.toJSON name}] = ${toPhp value};";

  defaultDeclarativeSettings = {
    db_name = cfg.database.name;
    db_host = cfg.database.host;
    db_user = cfg.database.user;
    db_port = cfg.database.port;
    file_storage_path = toString stateDir;
    tmpdir = "${stateDir}/tmp";
    debug = cfg.debug;
    sseEnabled = cfg.sseEnabled;
  }
  // lib.optionalAttrs (cfg.database.passwordFile == null) {
    db_pass = "";
  };

  declarativeSettings = defaultDeclarativeSettings // cfg.settings;

  declarativeConfig = pkgs.writeText "groupoffice-config.php" ''
    <?php
    ${lib.concatStringsSep "\n" (
      map (name: mkConfigLine name declarativeSettings.${name}) (lib.attrNames declarativeSettings)
    )}
    ${optionalString (cfg.database.passwordFile != null)
      "$config['db_pass'] = trim(file_get_contents(${builtins.toJSON (toString cfg.database.passwordFile)}));"
    }
  '';
in
{
  options.services.groupoffice = {
    enable = mkEnableOption "GroupOffice web application";

    package =
      mkPackageOption pkgs "groupoffice" { }
      // mkOption {
        apply =
          package:
          if package ? override then
            package.override { withSourceGuardian = cfg.enableSourceGuardian; }
          else
            package;
      };

    enableSourceGuardian = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable the unfree SourceGuardian PHP extension.
        This is required for some professional GroupOffice modules.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "groupoffice";
      description = "User account under which GroupOffice runs.";
    };

    group = mkOption {
      type = types.str;
      default = "groupoffice";
      description = "Group account under which GroupOffice runs.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/groupoffice";
      description = "State directory for GroupOffice data and mutable configuration.";
    };

    setupMode = mkOption {
      type = types.enum [
        "declarative"
        "web-installer"
      ];
      default = "declarative";
      description = ''
        Configuration mode.
        Use `declarative` to generate `config.php` from NixOS options.
        Use `web-installer` to keep `config.php` writable for the web installer.
      '';
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable GroupOffice debug mode in declarative setup mode.";
    };

    sseEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Server-Sent Events in declarative setup mode.";
    };

    settings = mkOption {
      type = with types; attrsOf anything;
      default = { };
      example = lib.literalExpression ''
        {
          checkForUpdates = false;
          nav_page_size = 200;
          support_link = "https://example.org/helpdesk";
        }
      '';
      description = ''
        Additional GroupOffice `$config` keys to write in declarative setup mode.
        This can be used to configure all options documented at
        <https://groupoffice.readthedocs.io/en/latest/install/config.html#configuration>.
      '';
    };

    database = {
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "Database host address.";
      };

      port = mkOption {
        type = types.port;
        default = 3306;
        description = "Database host port.";
      };

      name = mkOption {
        type = types.str;
        default = "groupoffice";
        description = "Database name.";
      };

      user = mkOption {
        type = types.str;
        default = "groupoffice";
        description = "Database user.";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/secrets/groupoffice-db-password";
        description = ''
          A file containing the database password for `database.user`.
        '';
      };

      createLocally = mkOption {
        type = types.bool;
        default = false;
        description = "Create the database and user locally with MariaDB.";
      };
    };

    virtualHost = mkOption {
      type = types.submodule (import ../web-servers/apache-httpd/vhost-options.nix);
      default = { };
      example = lib.literalExpression ''
        {
          hostName = "groupoffice.example.org";
          adminAddr = "webmaster@example.org";
          forceSSL = true;
          enableACME = true;
        }
      '';
      description = ''
        Apache configuration can be done by adapting {option}`services.httpd.virtualHosts`.
        See [](#opt-services.httpd.virtualHosts) for further information.
      '';
    };

    poolConfig = mkOption {
      type =
        with types;
        attrsOf (oneOf [
          str
          int
          bool
        ]);
      default = {
        "pm" = "dynamic";
        "pm.max_children" = 32;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 2;
        "pm.max_spare_servers" = 4;
        "pm.max_requests" = 500;
      };
      description = ''
        Options for the GroupOffice PHP pool. See the documentation on `php-fpm.conf`
        for details on configuration directives.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.database.createLocally -> cfg.database.user == user;
        message = "services.groupoffice.database.user must match services.groupoffice.user if createLocally is enabled";
      }
      {
        assertion = cfg.database.createLocally -> cfg.database.passwordFile == null;
        message = "services.groupoffice.database.passwordFile must be null when createLocally is enabled";
      }
    ];

    users.users = mkIf (cfg.user == "groupoffice") {
      groupoffice = {
        isSystemUser = true;
        inherit group;
      };
    };

    users.groups = mkIf (cfg.group == "groupoffice") { groupoffice = { }; };

    services.mysql = mkIf cfg.database.createLocally {
      enable = true;
      package = mkDefault pkgs.mariadb;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensurePermissions = {
            "${cfg.database.name}.*" = "ALL PRIVILEGES";
          };
        }
      ];
    };

    systemd.tmpfiles.rules = [
      "d '/etc/groupoffice' 0755 root root - -"
      "L+ '/etc/groupoffice/config.php' - - - - ${configFile}"
      "d '${stateDir}' 0750 ${user} ${group} - -"
      "d '${stateDir}/tmp' 0750 ${user} ${group} - -"
      "d '${stateDir}/cache' 0750 ${user} ${group} - -"
    ];

    systemd.services.groupoffice-setup = {
      description = "GroupOffice setup";
      wantedBy = [ "multi-user.target" ];
      before = [ "phpfpm-groupoffice.service" ];
      after = optional cfg.database.createLocally "mysql.service";

      serviceConfig = {
        Type = "oneshot";
      };

      script = ''
        install -d -m 0750 -o ${user} -g ${group} ${stateDir} ${stateDir}/tmp ${stateDir}/cache

        if [ "${cfg.setupMode}" = "declarative" ]; then
          install -m 0640 -o ${user} -g ${group} ${declarativeConfig} ${configFile}
        else
          if [ ! -e ${configFile} ]; then
            install -m 0660 -o ${user} -g ${group} ${cfg.package}/share/groupoffice/config.php.example ${configFile}
          fi
          chmod u+w ${configFile}
        fi
      '';
    };

    services.phpfpm.pools.groupoffice = {
      inherit user group;
      phpPackage = cfg.package.php;
      settings = {
        "listen.owner" = config.services.httpd.user;
        "listen.group" = config.services.httpd.group;
      }
      // cfg.poolConfig;
    };

    services.httpd = {
      enable = true;
      adminAddr = mkDefault cfg.virtualHost.adminAddr;
      extraModules = [ "proxy_fcgi" ];
      virtualHosts.${cfg.virtualHost.hostName} = mkMerge [
        cfg.virtualHost
        {
          documentRoot = lib.mkForce "${cfg.package}/share/groupoffice";
          extraConfig = ''
            <Directory "${cfg.package}/share/groupoffice">
              Require all granted
              AllowOverride None
              Options FollowSymLinks
              DirectoryIndex index.php

              <FilesMatch "\.php$">
                <If "-f %{REQUEST_FILENAME}">
                  SetHandler "proxy:unix:${fpm.socket}|fcgi://localhost/"
                </If>
              </FilesMatch>
            </Directory>

            Alias /public ${cfg.package}/share/groupoffice/public.php
            Alias /Microsoft-Server-ActiveSync ${cfg.package}/share/groupoffice/modules/z-push/index.php
            Alias /dav ${cfg.package}/share/groupoffice/go/core/dav/index.php
            Alias /caldav ${cfg.package}/share/groupoffice/modules/caldav/calendar.php
            Alias /carddav ${cfg.package}/share/groupoffice/modules/carddav/addressbook.php
            Alias /webdav ${cfg.package}/share/groupoffice/modules/dav/files.php
            Alias /wopi ${cfg.package}/share/groupoffice/go/modules/community/wopi/wopi.php
            Alias /gauth ${cfg.package}/share/groupoffice/go/modules/community/googleoauth2/gauth.php
            Alias /onlyoffice ${cfg.package}/share/groupoffice/go/modules/business/onlyoffice/connector.php
            Alias /mail/config-v1.1.xml ${cfg.package}/share/groupoffice/go/modules/community/autoconfig/autoconfig.php
            Alias /v1.1/mail/config-v1.1.xml ${cfg.package}/share/groupoffice/go/modules/community/autoconfig/autoconfig.php
            Alias /.well-known/autoconfig/mail/config-v1.1.xml ${cfg.package}/share/groupoffice/go/modules/community/autoconfig/autoconfig.php
            Alias /autodiscover/autodiscover.json ${cfg.package}/share/groupoffice/go/modules/community/autoconfig/autodiscover-json.php
            Alias /Autodiscover/Autodiscover.xml ${cfg.package}/share/groupoffice/go/modules/community/autoconfig/autodiscover.php
            Alias /autodiscover/autodiscover.xml ${cfg.package}/share/groupoffice/go/modules/community/autoconfig/autodiscover.php
            Alias /.well-known/openid-configuration ${cfg.package}/share/groupoffice/api/oauth.php/.well-known/openid-configuration

            Redirect 301 /.well-known/carddav /dav
            Redirect 301 /.well-known/caldav /dav

            <IfModule reqtimeout_module>
              RequestReadTimeout header=0
              RequestReadTimeout body=0
            </IfModule>
          '';
        }
      ];
    };

    systemd.services.groupoffice-cron = {
      description = "GroupOffice cron service";
      after = [ "groupoffice-setup.service" ];
      path = [ cfg.package.php ];
      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
      };
      script = ''
        ${cfg.package.php}/bin/php ${cfg.package}/share/groupoffice/cron.php /etc/groupoffice/config.php
      '';
    };

    systemd.timers.groupoffice-cron = {
      wantedBy = [ "timers.target" ];
      partOf = [ "groupoffice-cron.service" ];
      timerConfig = {
        OnCalendar = "*:0/1";
        AccuracySec = "30s";
        Persistent = true;
      };
    };

    services.groupoffice.virtualHost = {
      hostName = mkDefault config.networking.fqdnOrHostName;
      adminAddr = mkDefault "webmaster@localhost";
    };
  };
}
