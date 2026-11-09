class AddTaskLinkCheckToReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :reviews, :task_link_status, :string
    add_column :reviews, :task_link_note, :text
  end
end
