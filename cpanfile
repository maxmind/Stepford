requires "Carp" => "0";
requires "File::Temp" => "0";
requires "Forest::Tree" => "0";
requires "List::AllUtils" => "0";
requires "Log::Dispatch" => "0";
requires "Log::Dispatch::Null" => "0";
requires "Memory::Stats" => "0";
requires "Module::Pluggable::Object" => "0";
requires "Moose" => "0";
requires "Moose::Role" => "0";
requires "MooseX::Params::Validate" => "0";
requires "MooseX::StrictConstructor" => "0";
requires "MooseX::Types" => "0";
requires "MooseX::Types::Combine" => "0";
requires "MooseX::Types::Common::Numeric" => "0";
requires "MooseX::Types::Common::String" => "0";
requires "MooseX::Types::Moose" => "0";
requires "MooseX::Types::Path::Class" => "0";
requires "Parallel::ForkManager" => "0";
requires "Path::Class" => "0";
requires "Scalar::Util" => "0";
requires "Scope::Guard" => "0";
requires "Throwable::Error" => "0";
requires "Time::HiRes" => "1.9726";
requires "Try::Tiny" => "0";
requires "namespace::autoclean" => "0";
requires "parent" => "0";
requires "perl" => "5.010";
requires "strict" => "0";
requires "warnings" => "0";

on 'test' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "File::Copy" => "0";
  requires "File::Spec" => "0";
  requires "IPC::Signal" => "0";
  requires "Log::Dispatch::Array" => "0";
  requires "Test::Differences" => "0";
  requires "Test::Fatal" => "0";
  requires "Test::More" => "0.96";
  requires "Test::Requires" => "0";
  requires "Test::Warnings" => "0";
  requires "autodie" => "0";
  requires "lib" => "0";
  requires "perl" => "5.010";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "2.120900";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "perl" => "5.006";
};

on 'develop' => sub {
  requires "Code::TidyAll::Plugin::Test::Vars" => "0";
  requires "File::Spec" => "0";
  requires "IO::Handle" => "0";
  requires "IPC::Open3" => "0";
  requires "IPC::Signal" => "0";
  requires "Perl::Critic" => "1.123";
  requires "Perl::Tidy" => "20140711";
  requires "Pod::Coverage::TrustPod" => "0";
  requires "Test::CPAN::Changes" => "0.19";
  requires "Test::Code::TidyAll" => "0.24";
  requires "Test::EOL" => "0";
  requires "Test::More" => "0.88";
  requires "Test::NoTabs" => "0";
  requires "Test::Pod" => "1.41";
  requires "Test::Pod::Coverage" => "1.08";
  requires "Test::Portability::Files" => "0";
  requires "Test::Spelling" => "0.12";
  requires "Test::Version" => "1";
};
