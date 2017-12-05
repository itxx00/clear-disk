%define debug_package %{nil}
%define base_install_dir /usr/local/%{name}

Name:           clear-disk
Version:        1.0
Release:        2
Summary:        clear-disk for TBDS
License:        GPL

Group:          System Environment/Daemons
Source0:        clear-disk-%version.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArchitectures: noarch


Provides: clear-disk

%description
clear-disk for TBDS

%prep
%setup -q -n %{name}-%{version}

%build
true

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/usr/local/clear-disk
/bin/cp -r * $RPM_BUILD_ROOT/usr/local/clear-disk

%pre

%post

%preun
if [ $1 -eq 0 ]; then
    /usr/local/clear-disk/bin/clear_disk.sh stop >/dev/null 2>&1
fi

%postun
if [ $1 -eq 0 ]; then
  rm -rf /usr/local/clear-disk
fi


%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%config(noreplace) /usr/local/clear-disk/conf/*
%dir %{base_install_dir}
%{base_install_dir}/bin/*


%changelog
* Sun Aug 06 2017 itxx00 <itxx00@gmail.com> - 1.0-2
- init
