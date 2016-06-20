# noinspection ALL
class IssueTemplatesController < ApplicationController
  unloadable
  layout 'base'
  include IssueTemplatesHelper
  helper :issues
  include IssuesHelper
  menu_item :issues
  before_filter :find_object, only: [:show, :edit, :destroy]
  before_filter :find_user, :find_project, :authorize,
                except: [:preview, :move_order_higher, :move_order_lower, :move_order_to_top, :move_order_to_bottom, :move]
  before_filter :find_tracker, only: [:set_pulldown]

  def index
    project_id = @project.id
    project_templates = IssueTemplate.search_by_project(project_id)

    # pick up used tracker ids
    tracker_ids = project_templates.collect(&:tracker).uniq.sort.collect(&:id)

    @template_map = {}
    tracker_ids.each do |tracker_id|
      templates = project_templates.search_by_tracker(tracker_id).order_by_position
      @template_map[Tracker.find(tracker_id)] = templates if templates.any?
    end

    setting = IssueTemplateSetting.find_or_create(project_id)
    inherit_template = setting.enabled_inherit_templates?
    @inherit_templates = []

    project_ids = inherit_template ? @project.ancestors.collect(&:id) : [project_id]
    if inherit_template
      # keep ordering
      used_tracker_ids = @project.trackers.pluck(:tracker_id)
      @inherit_templates = get_inherit_templates(project_ids, used_tracker_ids)
    end

    @global_issue_templates = GlobalIssueTemplate.joins(:projects)
                                                 .search_by_project(project_id)
                                                 .order_by_position

    render layout: !request.xhr?
  end

  def show
    if @project != @issue_template.project
      render_403
      return
    end
  end

  def new
    # create empty instance
    @issue_template ||= IssueTemplate.new(author: @user, project: @project)
    if request.post?
      @issue_template.safe_attributes = params[:issue_template]
      if @issue_template.save
        flash[:notice] = l(:notice_successful_create)
        redirect_to action: 'show', id: @issue_template.id, project_id: @project
      end
    end
  end

  def edit
    # Change from request.post to request.patch for Rails4.
    if request.patch? || request.put?
      @issue_template.safe_attributes = params[:issue_template]
      if @issue_template.save
        flash[:notice] = l(:notice_successful_update)
        redirect_to action: 'show', id: @issue_template.id, project_id: @project
      end
    end
  end

  def destroy
    if request.post?
      if @issue_template.destroy
        flash[:notice] = l(:notice_successful_delete)
        redirect_to action: 'index', project_id: @project
      end
    end
  end

  # load template description
  def load
    issue_template_id = params[:issue_template]
    template_type = params[:template_type]
    @issue_template = if !template_type.blank? && template_type == 'global'
                        GlobalIssueTemplate.find(issue_template_id)
                      else
                        IssueTemplate.find(issue_template_id)
                      end
    render text: @issue_template.to_json(root: true)
  end

  # update pulldown
  def set_pulldown
    grouped_options = []
    group = []
    default_template = nil
    project_id = @project.id
    tracker_id = @tracker.id
    setting = IssueTemplateSetting.find_or_create(project_id)
    inherit_template = setting.enabled_inherit_templates?

    project_ids = inherit_template ? @project.ancestors.collect(&:id) : [project_id]
    issue_templates = IssueTemplate.search_by_project(project_id)
                                   .search_by_tracker(tracker_id)
                                   .enabled.order_by_position

    project_default_template = issue_templates.is_default.first

    has_project_default_template = project_default_template.present?
    default_template = nil

    if has_project_default_template
      default_template = project_default_template.id
    end

    unless issue_templates.empty?
      issue_templates.each { |x| group.push([x.title, x.id]) }
    end

    if inherit_template
      inherit_templates = get_inherit_templates(project_ids, tracker_id)

      if inherit_templates.any?
        inherit_templates.each do |template|
          group.push([template.title, template.id, { class: 'inherited' }])
          next unless template.is_default == true
          default_template = template unless has_project_default_template
        end
      end
    end

    global_issue_templates = GlobalIssueTemplate.joins(:projects)
                                                .search_by_tracker(tracker_id)
                                                .search_by_project(project_id)
                                                .order_by_position

    if global_issue_templates.any?
      global_issue_templates.each do |global_issue_template|
        group.push([global_issue_template.title, global_issue_template.id, { class: 'global' }])
      end
    end

    is_triggered_by_status = request.parameters[:is_triggered_by_status]
    grouped_options.push([@tracker.name, group]) if group.any?
    render action: '_template_pulldown', layout: false,
           locals: { is_triggered_by_status: is_triggered_by_status, grouped_options: grouped_options,
                     should_replaced: setting.should_replaced, default_template: default_template }
  end

  # preview
  def preview
    issue_template = params[:issue_template]
    @text = (issue_template ? issue_template[:description] : nil)
    render partial: 'common/preview'
  end

  # Reorder templates
  def move
    move_order(params[:to])
  end

  private

  def find_user
    @user = User.current
  end

  def find_tracker
    @tracker = Tracker.find(params[:issue_tracker_id])
  end

  def find_object
    @issue_template = IssueTemplate.find(params[:id])
    @project = @issue_template.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def move_order(method)
    IssueTemplate.find(params[:id]).send "move_#{method}"
    respond_to do |format|
      format.html { redirect_to action: 'index' }
      format.xml  { head :ok }
    end
  end

  def get_inherit_templates(project_ids, tracker_id)
    # keep ordering of project tree
    # TODO: Add Test code.
    inherit_templates = []
    project_ids.each do |i|
      inherit_templates.concat(IssueTemplate.search_by_project(i)
                                   .search_by_tracker(tracker_id)
                                   .enabled
                                   .enabled_sharing
                                   .order_by_position)
    end
    inherit_templates
  end
end
