require 'spec_helper'

describe "AlphaInstaller" do

  it "must be defined" do
    AlphaInstaller::VERSION.should_not be_nil
  end

  context "installation", :vcr => { :cassette_name => "installation" } do

    before do
      @installer = AlphaInstaller::Base.new( "alphainstaller",
        api_key: CONFIGURATION_DEFAULTS[:api_key]
      )
    end

    it "should create a new app with the specified name" do
      @installer.install.status.should eq 202
    end

  end

  # Will spec out once https://github.com/vcr/vcr/issues/199 is resolved
  #
  # context "openredis", :vcr => { :cassette_name => "installation" } do

  #   before do
  #     @installer = AlphaInstaller::Base.new( "alphainstaller",
  #       api_key: CONFIGURATION_DEFAULTS[:api_key],
  #       addons: [ 'openredis' ]
  #     )
  #   end

  #   it "shoud install openredis" do
  #     @installer.add_openredis.status.should eq 200
  #   end

  # end

end

