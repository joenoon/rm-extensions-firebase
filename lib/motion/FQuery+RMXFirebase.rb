class FQuery

  def [](*names)
    if names.length == 0
      childByAutoId
    else
      childByAppendingPath(names.join('/'))
    end
  end

  def limited(limit)
    queryLimitedToNumberOfChildren(limit)
  end

  def starting_at(priority, child_name=nil)
    if child_name
      queryStartingAtPriority(priority, andChildName:child_name)
    else
      queryStartingAtPriority(priority)
    end
  end

  def ending_at(priority, child_name=nil)
    if child_name
      queryEndingAtPriority(priority, andChildName:child_name)
    else
      queryEndingAtPriority(priority)
    end
  end

  def ref_description
    "https://#{repo.repoInfo.host}#{path.toString}##{queryParams.queryIdentifier}"
  end

end
