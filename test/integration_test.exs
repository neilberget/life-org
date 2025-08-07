defmodule LifeOrg.IntegrationTest do
  use ExUnit.Case
  alias LifeOrg.{LinkDetector, Integrations.Registry, Integrations.Decorators.WebLink}

  describe "Link Detection" do
    test "extracts URLs from text" do
      content = "Check out https://example.com and also visit https://github.com/user/repo"
      
      urls = LinkDetector.extract_urls(content)
      
      assert length(urls) == 2
      assert Enum.any?(urls, fn u -> u.url == "https://example.com" end)
      assert Enum.any?(urls, fn u -> u.url == "https://github.com/user/repo" end)
    end

    test "handles www URLs without protocol" do
      content = "Visit www.example.com for more info"
      
      urls = LinkDetector.extract_urls(content)
      
      assert length(urls) == 1
      assert hd(urls).url == "https://www.example.com"
    end
  end

  describe "Web Link Decorator" do
    test "matches HTTP and HTTPS URLs" do
      assert WebLink.match_url("https://example.com")
      assert WebLink.match_url("http://example.com")
      refute WebLink.match_url("ftp://example.com")
      refute WebLink.match_url("not-a-url")
    end

    test "has correct integration properties" do
      assert WebLink.name() == "Generic Web Link"
      assert WebLink.provider() == :web
      assert WebLink.priority() == 1
      assert :fetch_metadata in WebLink.capabilities()
    end
  end

  describe "Integration Registry" do
    test "registry is available" do
      # Test that the registry process is running
      assert Process.whereis(LifeOrg.Integrations.Registry) != nil
    end

    test "can find decorators for URLs" do
      decorators = Registry.get_decorators_for_url("https://example.com")
      
      # Should have at least the WebLink decorator
      assert length(decorators) >= 1
      assert WebLink in decorators
    end
  end
end