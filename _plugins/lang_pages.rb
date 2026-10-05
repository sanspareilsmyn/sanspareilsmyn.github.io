# Creates /kr/ and /en/ versions of every post and main page.
module LangPages
  class Generator < Jekyll::Generator
    LANGS = { "kr" => "ko", "en" => "en" }

    def generate(site)
      sources = site.posts.docs + site.pages.select { |p| p.ext == ".md" }
      sources.each do |src|
        base = src.url.chomp("/")
        LANGS.each do |segment, lang|
          page = Jekyll::PageWithoutAFile.new(site, site.source, base, "#{segment}.md")
          page.content = src.content
          page.data.merge!(src.data)
          page.data["lang"] = lang
          page.data["permalink"] = "#{base}/#{segment}/"
          site.pages << page
        end
      end
    end
  end
end
