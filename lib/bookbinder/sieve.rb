class Sieve
  def initialize(domain: ->(){ raise 'You must supply a domain parameter.' }.call)
    @unverified_fragments_by_url = {}
    @domain = domain
  end

  def links_from(page, is_first_pass)
    broken_links = []
    working_links = []

    if page.not_found? && is_first_pass
      broken_links << Spider.prepend_location(page.referer, page.url)
    else
      working_links << page.url.to_s
      broken_links.concat broken_fragments_targeting(page, is_first_pass)
      @unverified_fragments_by_url.merge! fragments_targeting_other_pages_from page
    end

    return broken_links, working_links
  end

  private

  def broken_fragments_targeting(page, first_pass)
    first_pass ? local_fragments_missing_from(page) : remote_fragments_missing_from(page)
  end

  def local_fragments_missing_from(page)
    local_fragments = page.fragment_identifiers targeting_locally: true
    local_fragments.map { |uri| Spider.prepend_location(page.url, uri) unless page.has_target_for?(uri) }.compact
  end

  def fragments_targeting_other_pages_from(page)
    uris_with_fragments = page.fragment_identifiers(targeting_locally: false)
    uris_with_fragments.reduce({}) { |dict, uri| merge_uris_under_targets(dict, page, uri) }
  end

  def merge_uris_under_targets(dict, page, uri)
    target_url = URI::join @domain, uri.path
    localized_identifier = Spider.prepend_location(page.url, "##{uri.fragment}")

    if dict.has_key? target_url
      dict[target_url] << localized_identifier
    else
      dict[target_url] = [localized_identifier]
    end

    dict
  end

  def remote_fragments_missing_from(page)
    @unverified_fragments_by_url.fetch(page.url, []).reject { |localized_identifier| page.has_target_for? URI(strip_location(localized_identifier)) }
  end

  def strip_location(id)
    id.split('=> ').last
  end
end
