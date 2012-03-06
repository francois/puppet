begin test_name "puppet module upgrade (with local changes)"

step 'Setup'
require 'resolv'; ip = Resolv.getaddress('forge-dev.puppetlabs.com')
apply_manifest_on master, "host { 'forge.puppetlabs.com': ip => '#{ip}' }"
apply_manifest_on master, "file { ['/etc/puppet/modules', '/usr/share/puppet/modules']: recurse => true, purge => true, force => true }"
on master, puppet("module install pmtacceptance-java --version 1.6.0")
on master, puppet("module list") do
  assert_output <<-OUTPUT
    /etc/puppet/modules
    ├── pmtacceptance-java (v1.6.0)
    └── pmtacceptance-stdlib (v1.0.0)
    /usr/share/puppet/modules (no modules installed)
  OUTPUT
end
apply_manifest_on master, <<-PP
  file {
    '/etc/puppet/modules/java/README': content => "I CHANGE MY READMES";
    '/etc/puppet/modules/java/NEWFILE': content => "I don't exist.'";
  }
PP

step "Try to upgrade a module with local changes"
on master, puppet("module upgrade pmtacceptance-java"), :acceptable_exit_codes => [1] do
  assert_output <<-OUTPUT
    STDOUT> Finding module 'pmtacceptance-java' in module path ...
    STDOUT> Preparing to upgrade /etc/puppet/modules/java ...
    STDOUT> Downloading from http://forge.puppetlabs.com ...
    STDERR> \e[1;31mError: Could not upgrade module 'pmtacceptance-java' (v1.6.0 -> latest: v1.7.1)
    STDERR>   Installed module has had changes made locally
    STDERR>     Use `puppet module upgrade --force` to upgrade this module anyway\e[0m
  OUTPUT
end
on master, '[[ "$(cat /etc/puppet/modules/java/README)" == "I CHANGE MY READMES" ]]'
on master, '[ -f /etc/puppet/modules/java/NEWFILE ]'

step "Upgrade a module with local changes with --force"
on master, puppet("module upgrade pmtacceptance-java --force") do
  assert_output <<-OUTPUT
    Finding module 'pmtacceptance-java' in module path ...
    Preparing to upgrade /etc/puppet/modules/java ...
    Downloading from http://forge.puppetlabs.com ...
    Upgrading -- do not interrupt ...
    /etc/puppet/modules
    └── pmtacceptance-java (v1.6.0 -> v1.7.1)
  OUTPUT
end
on master, '[[ "$(cat /etc/puppet/modules/java/README)" != "I CHANGE MY READMES" ]]'
on master, '[ ! -f /etc/puppet/modules/java/NEWFILE ]'

ensure step "Teardown"
apply_manifest_on master, "host { 'forge.puppetlabs.com': ensure => absent }"
apply_manifest_on master, "file { ['/etc/puppet/modules', '/usr/share/puppet/modules']: recurse => true, purge => true, force => true }"
end
