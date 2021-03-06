require 'spec_helper'
require 'rspec'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'sqlserver_spec_helper.rb'))
require 'mocha'

provider_class = Puppet::Type.type(:sqlserver_features).provider(:mssql)

RSpec.describe provider_class do
  subject { provider_class }
  let(:params) { {
    :name => 'Base features',
    :source => 'C:\myinstallexecs',
    :features => %w(BC SSMS)
  } }
  let(:additional_params) { {} }
  let(:munged_args) { {} }
  let(:additional_switches) { [] }
  shared_examples 'create' do |exit_code, warning_matcher|
    it {
      params.merge!(additional_params)
      @resource = Puppet::Type::Sqlserver_features.new(params)
      @provider = provider_class.new(@resource)

      stub_powershell_call(subject)

      executed_args = params.merge(munged_args)
      stub_add_features(executed_args, executed_args[:features], additional_switches, exit_code || 0)
      @provider.stubs(:warn).with(regexp_matches(warning_matcher)).returns(nil).times(1) if warning_matcher
      @provider.create
    }
  end

  shared_context 'features' do
    @feature_params = {
      :name => 'Base features',
      :source => 'C:\myinstallexecs',
      :features => %w(BC SSMS)
    }
    let(:feature_remove) { [] }
    let(:feature_add) { [] }
  end

  context 'it should provide the correct command default command' do
    include_context 'features'
    it_should_behave_like 'create'
  end

  context 'it should provide the correct command default command' do
    before :each do
      @file_double = Tempfile.new(['sqlconfig', '.ini'])
      @file_double.stubs(:write)
      @file_double.stubs(:flush)
      @file_double.stubs(:close)
      Tempfile.stubs(:new).with(['sqlconfig', '.ini']).returns(@file_double)
    end
    it_should_behave_like 'create' do
      let(:additional_params) { {:install_switches => {'ERRORREPORTING' => 1, 'SQLBACKUPDIR' => 'I:\DBbackup'}} }
      let(:additional_switches) { ["/ConfigurationFile=\"#{@file_double.path}\""] }
    end
  end

  # context 'it should expand the superset for features' do
  #   include_context 'features'
  #   let(:additional_params) { {:features => %w(Tools)} }
  #   let(:munged_args) { {:features => %w(ADV_SSMS BC Conn SDK SSMS)} }
  #   it_should_behave_like 'create'
  # end

  shared_examples 'features=' do |args, exit_code, warning_matcher|
    it {
      @resource = Puppet::Type::Sqlserver_features.new(args)
      @provider = provider_class.new(@resource)

      stub_powershell_call(subject)
      stub_source_which_call args
      if !feature_remove.empty?
        stub_remove_features(args, feature_remove, exit_code || 0)
      end
      if !feature_add.empty?
        stub_add_features(args, feature_add, [], exit_code || 0)
      end

      # If warning_matcher supplied ensure warnings raised match, otherwise no warnings raised
      @provider.stubs(:warn).with(regexp_matches(warning_matcher)).returns(nil).times(1) if warning_matcher
      @provider.stubs(:warn).with(anything).times(0) unless warning_matcher
      @provider.create
    }
  end

  shared_examples 'fail on' do |feature_params|
    it {
      expect {
        @resource = Puppet::Type::Sqlserver_features.new(feature_params)
        @provider = provider_class.new(@resource)

        stub_powershell_call(subject)

        stub_source_which_call feature_params[:source]

        @provider.create
      }.to raise_error Puppet::ResourceError

    }
  end

  context 'it should install SSMS' do
    include_context 'features'
    @feature_params[:features] = %w(SSMS)
    let(:feature_add) { %w(SSMS) }
    it_should_behave_like 'features=', @feature_params
  end

  context 'it should raise warning on feature install when 1641 exit code returned' do
    include_context 'features'
    @feature_params[:features] = %w(SSMS)
    let(:feature_add) { %w(SSMS) }
    it_should_behave_like 'features=', @feature_params, 1641, /reboot initiated/i
  end

  context 'it should raise warning on feature install when 3010 exit code returned' do
    include_context 'features'
    @feature_params[:features] = %w(SSMS)
    let(:feature_add) { %w(SSMS) }
    it_should_behave_like 'features=', @feature_params, 3010, /reboot required/i
  end

  # context 'it should install the expanded tools set' do
  #   include_context 'features'
  #   @feature_params[:features] = %w(Tools)
  #   let(:feature_add) { %w(ADV_SSMS BC Conn SDK SSMS) }
  #   it_should_behave_like 'features=', @feature_params
  # end

  describe 'it should call destroy on empty array' do
    it {
      feature_params = {
        :name => 'Base features',
        :source => 'C:\myinstallexecs',
        :features => []
      }
      @resource = Puppet::Type::Sqlserver_features.new(feature_params)
      @provider = provider_class.new(@resource)
      @provider.stubs(:current_installed_features).returns(%w(SSMS ADV_SSMS Conn))
      Puppet::Util.stubs(:which).with("#{feature_params[:source]}/setup.exe").returns("#{feature_params[:source]}/setup.exe")
      result = Puppet::Util::Execution::ProcessOutput.new('', 0)
      Puppet::Util::Execution.expects(:execute).with(
        ["#{feature_params[:source]}/setup.exe",
         "/ACTION=uninstall",
         '/Q',
         '/IACCEPTSQLSERVERLICENSETERMS',
         "/FEATURES=#{%w(SSMS ADV_SSMS Conn).join(',')}",
        ], failonfail: false).returns(result)
      @provider.create
    }
  end

  describe 'it should pass the is_credentials' do
    include_context 'features'
    @feature_params[:is_svc_account] = 'nexus/Administrator'
    @feature_params[:is_svc_password] = 'MycrazyStrongPassword'
    @feature_params[:features] << 'IS'
    let(:feature_add) { %w(BC IS SSMS) }
    it_should_behave_like 'features=', @feature_params
  end
end
