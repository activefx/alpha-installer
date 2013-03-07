require 'spec_helper'

describe "AlphaInstaller" do

  it "must be defined" do
    AlphaInstaller::VERSION.should_not be_nil
  end

end

