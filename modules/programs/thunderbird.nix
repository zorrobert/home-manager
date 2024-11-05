{ config, lib, pkgs, ... }:

with lib;

let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  cfg = config.programs.thunderbird;

  thunderbirdJson = types.attrsOf (pkgs.formats.json { }).type // {
    description =
      "Thunderbird preference (int, bool, string, and also attrs, list, float as a JSON string)";
  };

  enabledAccounts = attrValues
    (filterAttrs (_: a: a.thunderbird.enable) config.accounts.email.accounts);

  enabledAccountsWithId =
    map (a: a // { id = builtins.hashString "sha256" a.name; }) enabledAccounts;

  thunderbirdConfigPath =
    if isDarwin then "Library/Thunderbird" else ".thunderbird";

  thunderbirdProfilesPath = if isDarwin then
    "${thunderbirdConfigPath}/Profiles"
  else
    thunderbirdConfigPath;

  profilesWithId =
    imap0 (i: v: v // { id = toString i; }) (attrValues cfg.profiles);

  profilesIni = foldl recursiveUpdate {
    General = {
      StartWithLastProfile = 1;
      Version = 2;
    };
  } (flip map profilesWithId (profile: {
    "Profile${profile.id}" = {
      Name = profile.name;
      Path = if isDarwin then "Profiles/${profile.name}" else profile.name;
      IsRelative = 1;
      Default = if profile.isDefault then 1 else 0;
    };
  }));

  toThunderbirdIdentity = account: address:
    # For backwards compatibility, the primary address reuses the account ID.
    let
      id = if address == account.address then
        account.id
      else
        builtins.hashString "sha256" address;
    in {
      "mail.identity.id_${id}.fullName" = account.realName;
      "mail.identity.id_${id}.useremail" = address;
      "mail.identity.id_${id}.valid" = true;
      "mail.identity.id_${id}.htmlSigText" =
        if account.signature.showSignature == "none" then
          ""
        else
          account.signature.text;
    } // optionalAttrs (account.gpg != null) {
      "mail.identity.id_${id}.attachPgpKey" = false;
      "mail.identity.id_${id}.autoEncryptDrafts" = true;
      "mail.identity.id_${id}.e2etechpref" = 0;
      "mail.identity.id_${id}.encryptionpolicy" =
        if account.gpg.encryptByDefault then 2 else 0;
      "mail.identity.id_${id}.is_gnupg_key_id" = true;
      "mail.identity.id_${id}.last_entered_external_gnupg_key_id" =
        account.gpg.key;
      "mail.identity.id_${id}.openpgp_key_id" = account.gpg.key;
      "mail.identity.id_${id}.protectSubject" = true;
      "mail.identity.id_${id}.sign_mail" = account.gpg.signByDefault;
    } // account.thunderbird.perIdentitySettings id;

  toThunderbirdAccount = account: profile:
    let
      id = account.id;
      addresses = [ account.address ] ++ account.aliases;
    in {
      "mail.account.account_${id}.identities" = concatStringsSep ","
        ([ "id_${id}" ]
          ++ map (address: "id_${builtins.hashString "sha256" address}")
          account.aliases);
      "mail.account.account_${id}.server" = "server_${id}";
    } // optionalAttrs account.primary {
      "mail.accountmanager.defaultaccount" = "account_${id}";
    } // optionalAttrs (account.imap != null) {
      "mail.server.server_${id}.directory" =
        "${thunderbirdProfilesPath}/${profile.name}/ImapMail/${id}";
      "mail.server.server_${id}.directory-rel" = "[ProfD]ImapMail/${id}";
      "mail.server.server_${id}.hostname" = account.imap.host;
      "mail.server.server_${id}.login_at_startup" = true;
      "mail.server.server_${id}.name" = account.name;
      "mail.server.server_${id}.port" =
        if (account.imap.port != null) then account.imap.port else 143;
      "mail.server.server_${id}.socketType" = if !account.imap.tls.enable then
        0
      else if account.imap.tls.useStartTls then
        2
      else
        3;
      "mail.server.server_${id}.type" = "imap";
      "mail.server.server_${id}.userName" = account.userName;
    } // optionalAttrs (account.smtp != null) {
      "mail.identity.id_${id}.smtpServer" = "smtp_${id}";
      "mail.smtpserver.smtp_${id}.authMethod" = 3;
      "mail.smtpserver.smtp_${id}.hostname" = account.smtp.host;
      "mail.smtpserver.smtp_${id}.port" =
        if (account.smtp.port != null) then account.smtp.port else 587;
      "mail.smtpserver.smtp_${id}.try_ssl" = if !account.smtp.tls.enable then
        0
      else if account.smtp.tls.useStartTls then
        2
      else
        3;
      "mail.smtpserver.smtp_${id}.username" = account.userName;
    } // optionalAttrs (account.smtp != null && account.primary) {
      "mail.smtp.defaultserver" = "smtp_${id}";
    } // builtins.foldl' (a: b: a // b) { }
    (builtins.map (address: toThunderbirdIdentity account address) addresses)
    // account.thunderbird.settings id;

  toThunderbirdCalendar = calendar: (
    attrsets.filterAttrs (n: v: (v != null) && (v != "") ) (
      builtins.foldl' (a: b: a // b) { } (
        builtins.map (
          calendarName:
            let
              calendarHash = builtins.hashString "md5" calendar."${calendarName}".remote.url;
              cal = calendar."${calendarName}";
            in {
              #"calendar.registry.${calendarHash}.auto-enabled" = true;
              #"calendar.registry.${calendarHash}.disabled" = false;
              "calendar.registry.${calendarHash}.name" = calendar."${calendarName}".name;
              # remote settings
              "calendar.registry.${calendarHash}.uri" = calendar."${calendarName}".remote.url;
              "calendar.registry.${calendarHash}.type" = if cal.remote.type == "http"
              then "ics"
              else cal.remote.type;
              "calendar.registry.${calendarHash}.username" = calendar."${calendarName}".remote.userName;
              # thunderbird settings
              "calendar.registry.${calendarHash}.cache.enabled" = calendar."${calendarName}".thunderbird.cache.enabled;
              "calendar.registry.${calendarHash}.calendar-main-in-composite" = calendar."${calendarName}".thunderbird.calendar-main-in-composite;
              "calendar.registry.${calendarHash}.color" = calendar."${calendarName}".thunderbird.color;
              "calendar.registry.${calendarHash}.readOnly" = calendar."${calendarName}".thunderbird.readOnly;
            }
        )
        (
          builtins.attrNames (
            attrsets.filterAttrs (n: v: v.thunderbird.enable == true ) (calendar)
          )
        )
      )
    )
  );

  # convert the attrset config.accounts.contact.accounts into an attrset that can be merged into user.js
  toThunderbirdAddressBooks = addressBooks: (
    builtins.foldl' (a: b: a // b) { } (
      builtins.map (
        addressBook:
        let
          aBookID = addressBook; # remove spaces from string somehow
        in {
          "ldap_2.servers.${aBookID}.description" = addressBooks."${addressBook}".name;
          "ldap_2.servers.${aBookID}.filename" = "abook-${aBookID}.sqlite";
        } // optionalAttrs (addressBooks."${addressBook}".remote.type == "carddav") {
          # I think dirtype is set depending on the type of remote.target. seems to be 102 for remote.type = carddav.
          "ldap_2.servers.${aBookID}.dirType" = 102;

          "ldap_2.servers.${aBookID}.carddav.url" = addressBooks."${addressBook}".remote.url;
          "ldap_2.servers.${aBookID}.carddav.username" = addressBooks."${addressBook}".remote.userName;
        }
      ) (builtins.attrNames (
        attrsets.filterAttrs (n: v: v.thunderbird.enable == true ) (addressBooks)
      ))
    )
  );

  mkUserJs = prefs: extraPrefs: ''
    // Generated by Home Manager.

    ${concatStrings (mapAttrsToList (name: value: ''
      user_pref("${name}", ${builtins.toJSON value});
    '') prefs)}
    ${extraPrefs}
  '';
in {
  meta.maintainers = with hm.maintainers; [ d-dervishi jkarlson ];

  options = {
    programs.thunderbird = {
      enable = mkEnableOption "Thunderbird";

      package = mkOption {
        type = types.package;
        default = pkgs.thunderbird;
        defaultText = literalExpression "pkgs.thunderbird";
        example = literalExpression "pkgs.thunderbird-91";
        description = "The Thunderbird package to use.";
      };

      profiles = mkOption {
        type = with types;
          attrsOf (submodule ({ config, name, ... }: {
            options = {
              name = mkOption {
                type = types.str;
                default = name;
                readOnly = true;
                description = "This profile's name.";
              };

              isDefault = mkOption {
                type = types.bool;
                default = false;
                example = true;
                description = ''
                  Whether this is a default profile. There must be exactly one
                  default profile.
                '';
              };

              settings = mkOption {
                type = thunderbirdJson;
                default = { };
                example = literalExpression ''
                  {
                    "mail.spellcheck.inline" = false;
                    "mailnews.database.global.views.global.columns" = {
                      selectCol = {
                        visible = false;
                        ordinal = 1;
                      };
                      threadCol = {
                        visible = true;
                        ordinal = 2;
                      };
                    };
                  }
                '';
                description = ''
                  Preferences to add to this profile's
                  {file}`user.js`.
                '';
              };

              withExternalGnupg = mkOption {
                type = types.bool;
                default = false;
                example = true;
                description = "Allow using external GPG keys with GPGME.";
              };

              userChrome = mkOption {
                type = types.lines;
                default = "";
                description = "Custom Thunderbird user chrome CSS.";
                example = ''
                  /* Hide tab bar in Thunderbird */
                  #tabs-toolbar {
                    visibility: collapse !important;
                  }
                '';
              };

              userContent = mkOption {
                type = types.lines;
                default = "";
                description = "Custom Thunderbird user content CSS.";
                example = ''
                  /* Hide scrollbar on Thunderbird pages */
                  *{scrollbar-width:none !important}
                '';
              };

              extraConfig = mkOption {
                type = types.lines;
                default = "";
                description = ''
                  Extra preferences to add to {file}`user.js`.
                '';
              };

              search = mkOption {
                type = types.submodule (args:
                  import ./firefox/profiles/search.nix {
                    inherit (args) config;
                    inherit lib pkgs;
                    appName = "Thunderbird";
                    modulePath =
                      [ "programs" "thunderbird" "profiles" name "search" ];
                    profilePath = name;
                  });
                default = { };
                description = "Declarative search engine configuration.";
              };
            };
          }));
        description = "Attribute set of Thunderbird profiles.";
      };

      settings = mkOption {
        type = thunderbirdJson;
        default = { };
        example = literalExpression ''
          {
            "general.useragent.override" = "";
            "privacy.donottrackheader.enabled" = true;
          }
        '';
        description = ''
          Attribute set of Thunderbird preferences to be added to
          all profiles.
        '';
      };

      darwinSetupWarning = mkOption {
        type = types.bool;
        default = true;
        example = false;
        visible = isDarwin;
        readOnly = !isDarwin;
        description = ''
          Warn to set environment variables before using this module. Only
          relevant on Darwin.
        '';
      };
    };

    accounts.email.accounts = mkOption {
      type = with types;
        attrsOf (submodule {
          options.thunderbird = {
            enable =
              mkEnableOption "the Thunderbird mail client for this account";

            profiles = mkOption {
              type = with types; listOf str;
              default = [ ];
              example = literalExpression ''
                [ "profile1" "profile2" ]
              '';
              description = ''
                List of Thunderbird profiles for which this account should be
                enabled. If this list is empty (the default), this account will
                be enabled for all declared profiles.
              '';
            };

            settings = mkOption {
              type = with types; functionTo (attrsOf (oneOf [ bool int str ]));
              default = _: { };
              defaultText = literalExpression "_: { }";
              example = literalExpression ''
                id: {
                  "mail.server.server_''${id}.check_new_mail" = false;
                };
              '';
              description = ''
                Extra settings to add to this Thunderbird account configuration.
                The {var}`id` given as argument is an automatically
                generated account identifier.
              '';
            };

            perIdentitySettings = mkOption {
              type = with types; functionTo (attrsOf (oneOf [ bool int str ]));
              default = _: { };
              defaultText = literalExpression "_: { }";
              example = literalExpression ''
                id: {
                  "mail.identity.id_''${id}.protectSubject" = false;
                  "mail.identity.id_''${id}.autoEncryptDrafts" = false;
                };
              '';
              description = ''
                Extra settings to add to each identity of this Thunderbird
                account configuration. The {var}`id` given as
                argument is an automatically generated identifier.
              '';
            };
          };
        });
    };

    accounts.calendar.accounts = mkOption {
      type = with types;
        attrsOf (submodule {
          options.thunderbird = {
            enable =
              mkEnableOption "Enable Thunderbird for this calendar.";

            profiles = mkOption {
              type = with types; listOf str;
              default = [ ];
              example = literalExpression ''
                [ "profile1" "profile2" ]
              '';
              description = ''
                List of Thunderbird profiles for which this account should be
                enabled. If this list is empty (the default), this account will
                be enabled for all declared profiles.
              '';
            };

            calendar-main-in-composite = mkOption {
              type = types.bool;
              default = true;
              description = ''Whether this calendar should be shown by default.'';
            };

            cache.enabled = mkOption {
              type = types.bool;
              default = true;
              description = ''I honestly don't really know what this does.'';
            };

            color = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''Specify the color that should be used by Thunderbird for this calendar.'';
            };

            readOnly = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = ''Should the calendar be marked as read only in Thunderbird.'';
            };
          };
        });
    };

    accounts.contact.accounts = mkOption {
      type = with types;
        attrsOf (submodule {
          options.thunderbird = {
            enable =
              mkEnableOption "Enable Thunderbird for this Address Book.";

            profiles = mkOption {
              type = with types; listOf str;
              default = [ ];
              example = literalExpression ''
                [ "profile1" "profile2" ]
              '';
              description = ''
                List of Thunderbird profiles for which this account should be
                enabled. If this list is empty (the default), this account will
                be enabled for all declared profiles.
              '';
            };
          };
        });
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      (let defaults = catAttrs "name" (filter (a: a.isDefault) profilesWithId);
      in {
        assertion = cfg.profiles == { } || length defaults == 1;
        message = "Must have exactly one default Thunderbird profile but found "
          + toString (length defaults) + optionalString (length defaults > 1)
          (", namely " + concatStringsSep "," defaults);
      })

      (let
        profiles = catAttrs "name" profilesWithId;
        selectedProfiles =
          concatMap (a: a.thunderbird.profiles) enabledAccounts;
      in {
        assertion = (intersectLists profiles selectedProfiles)
          == selectedProfiles;
        message = "Cannot enable an account for a non-declared profile. "
          + "The declared profiles are " + (concatStringsSep "," profiles)
          + ", but the used profiles are "
          + (concatStringsSep "," selectedProfiles);
      })
    ];

    warnings = optional (isDarwin && cfg.darwinSetupWarning) ''
      Thunderbird packages are not yet supported on Darwin. You can still use
      this module to manage your accounts and profiles by setting
      'programs.thunderbird.package' to a dummy value, for example using
      'pkgs.runCommand'.

      Note that this module requires you to set the following environment
      variables when using an installation of Thunderbird that is not provided
      by Nix:

          export MOZ_LEGACY_PROFILES=1
          export MOZ_ALLOW_DOWNGRADE=1
    '';

    home.packages = [ cfg.package ]
      ++ optional (any (p: p.withExternalGnupg) (attrValues cfg.profiles))
      pkgs.gpgme;

    home.file = mkMerge ([{
      "${thunderbirdConfigPath}/profiles.ini" =
        mkIf (cfg.profiles != { }) { text = generators.toINI { } profilesIni; };
    }] ++ flip mapAttrsToList cfg.profiles (name: profile: {
      "${thunderbirdProfilesPath}/${name}/chrome/userChrome.css" =
        mkIf (profile.userChrome != "") { text = profile.userChrome; };

      "${thunderbirdProfilesPath}/${name}/chrome/userContent.css" =
        mkIf (profile.userContent != "") { text = profile.userContent; };

      "${thunderbirdProfilesPath}/${name}/user.js" = let
        accounts = filter (a:
          a.thunderbird.profiles == [ ]
          || any (p: p == name) a.thunderbird.profiles) enabledAccountsWithId;

        smtp = filter (a: a.smtp != null) accounts;
      in {
        text = mkUserJs (builtins.foldl' (a: b: a // b) { } ([
          cfg.settings

          (optionalAttrs (length accounts != 0) {
            "mail.accountmanager.accounts" =
              concatStringsSep "," (map (a: "account_${a.id}") accounts);
          })

          (optionalAttrs (length smtp != 0) {
            "mail.smtpservers" =
              concatStringsSep "," (map (a: "smtp_${a.id}") smtp);
          })

          { "mail.openpgp.allow_external_gnupg" = profile.withExternalGnupg; }

          profile.settings

          (toThunderbirdCalendar config.accounts.calendar.accounts)
          (toThunderbirdAddressBooks config.accounts.contact.accounts)
        ] ++ (map (a: toThunderbirdAccount a profile) accounts)))
          profile.extraConfig;
      };

      "${thunderbirdProfilesPath}/${name}/search.json.mozlz4" =
        mkIf (profile.search.enable) {
          enable = profile.search.enable;
          force = profile.search.force;
          source = profile.search.file;
        };
    }));
  };
}
