# == Class: drbd::base
#
# Basic class which installs the drbd modules and tools, and enables the service
# at boot time.
#
# Usage:
#
#   include drbd::base
#
# Require:
#
#   module kmod (git@github.com:camptocamp/puppet-kmod.git)
#
class drbd::base(
  $centos_mirror = 'http://mirror.switch.ch/ftp/mirror/centos/',
  $atrpms_mirror = 'http://ftp-stud.fht-esslingen.de/Mirrors/atrpms/dl.atrpms.net/',
) {

  case $::operatingsystem {

    'RedHat': {

      case $::lsbmajdistrelease {
        '6': {
          # ATrpms repository doesn't exist anymore, so we're pulling from a
          # mirror which is obviously not updated anymore. Don't have any
          # better alternative right now.

          yumrepo { 'atrpms-drbd':
            descr       => "DRBD packages from an ATrpms mirror for RHEL ${::lsbmajdistrelease}",
            baseurl     => "${atrpms_mirror}el6-${::architecture}/atrpms/stable",
            enabled     => 1,
            gpgcheck    => 0,
            includepkgs => 'drbd,drbd-kmdl-*',
          }

          # ensure file is managed in case we want to purge /etc/yum.repos.d/
          # http://projects.puppetlabs.com/issues/3152
          file { '/etc/yum.repos.d/atrpms-drbd.repo':
            ensure  => file,
            mode    => '0644',
            owner   => 'root',
            require => Yumrepo['atrpms-drbd'],
          }

          if $::virtual == 'xenu' {
            fail 'DRDB on a XEN instance not supported with RHEL6 yet, sorry.'
          }

          package { 'drbd':
            ensure  => present,
            require => [
              Yumrepo['atrpms-drbd'],
              File['/etc/yum.repos.d/atrpms-drbd.repo'],
            ],
          }

          package { 'drbd-module':
            ensure  => present,
            name    => "drbd-kmdl-${::kernelrelease}",
            require => [
              Yumrepo['atrpms-drbd'],
              File['/etc/yum.repos.d/atrpms-drbd.repo'],
            ],
            before  => Kmod::Load['drbd'],
          }

          # Should probably be created by the drbd package, but is not.
          file { '/var/lib/drbd':
            ensure => directory,
          }

        }
        default: {

          yumrepo { 'centos-extra-drbd':
            descr       => "DRBD packages from Centos-extras for RHEL ${::lsbmajdistrelease}",
            baseurl     => "${centos_mirror}${::lsbmajdistrelease}/extras/${::architecture}/",
            enabled     => 1,
            gpgkey      => "${centos_mirror}/RPM-GPG-KEY-CentOS-${::lsbmajdistrelease}",
            gpgcheck    => 1,
            includepkgs => 'drbd83,kmod-drbd83,kmod-drbd83-xen',
          }

          # ensure file is managed in case we want to purge /etc/yum.repos.d/
          # http://projects.puppetlabs.com/issues/3152
          file { '/etc/yum.repos.d/centos-extra-drbd.repo':
            ensure  => file,
            mode    => '0644',
            owner   => 'root',
            require => Yumrepo['centos-extra-drbd'],
          }

          if $::virtual == 'xenu' {
            $kmodpkg = 'kmod-drbd83-xen'
          } else {
            $kmodpkg = 'kmod-drbd83'
          }

          package { 'drbd':
            ensure  => present,
            name    => 'drbd83',
            require => Yumrepo['centos-extra-drbd'],
          }

          package { 'drbd-module':
            ensure  => present,
            name    => $kmodpkg,
            require => Yumrepo['centos-extra-drbd'],
            before  => Kmod::Load['drbd'],
          }

        }
      }


    }

    'Debian': {
      if $::lsbmajdistrelease == '6' {
        package { 'drbd':
          ensure => present,
          name   => 'drbd8-utils',
        }
      }
    }

    'Ubuntu': {
      package { 'drbd':
        ensure => present,
        name   => 'drbd8-utils',
      }

      package { 'drbd-module':
        ensure => present,
        name   => 'drbd8-source',
        before => Kmod::Load['drbd'],
      }
    }
  }

  kmod::load {'drbd': }

  augeas { 'remove legacy modprobe.conf install entry':
    incl    => '/etc/modprobe.d/modprobe.conf',
    lens    => 'Modprobe.lns',
    changes => "rm install[. = 'drbd']",
    onlyif  => "match install[. = 'drbd'] size > 0",
    before  => Kmod::Load['drbd'],
  }

  service { 'drbd':
    ensure    => running,
    hasstatus => true,
    restart   => '/etc/init.d/drbd reload',
    enable    => true,
    require   => [Package['drbd'], Kmod::Load['drbd']],
  }

  # this file just includes other files
  file { '/etc/drbd.conf':
    ensure  => file,
    mode    => '0644',
    owner   => 'root',
    content => '# file managed by puppet
include "/etc/drbd.conf.d/*.conf";
',
    require => Package['drbd'],
    before  => Service['drbd'],
    notify  => Service['drbd'],
  }

  # only allow files managed by puppet in this directory.
  file { '/etc/drbd.conf.d/':
    ensure  => directory,
    # lint:ignore:fileserver
    source  => 'puppet:///modules/drbd/drbd.conf.d/',
    # lint:endignore
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    purge   => true,
    recurse => true,
    force   => true,
    require => Package['drbd'],
    notify  => Service['drbd'],
  }

}
