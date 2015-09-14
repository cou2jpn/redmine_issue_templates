module IssueTemplatesHelper
  def project_tracker?(tracker_id, project)
    return true if project.trackers.exists?(tracker_id)
    false
  end

  def non_project_tracker_msg(flag)
    return '' if flag
    "<font class=\"non_project_tracker\">#{l(:unused_tracker_at_this_project)}</font>".html_safe
  end

  def template_target_trackers(project, issue_template)
    trackers = project.trackers
    trackers |= [issue_template.tracker] unless issue_template.tracker_id.blank?
    trackers = trackers.collect { |obj| [obj.name, obj.id] }
    trackers
  end

  def link_to_template(template, options={})
    if template.try(:project).present? && (template.project == @project || User.current.allowed_to?(:edit_issue_templates, template.project))
      link_to template.title, {:id => template.id, :project_id => template.project, :action => 'show'}, {:title => template.note}
    else
      template.title
    end
  end
end
