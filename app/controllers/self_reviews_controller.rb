# Zakładka self review strony wejściowej. Treść lewej kolumny liczy SelfReviewBoard
# (leniwie, przez DashboardShell), a ten kontroler tylko przełącza na nią zakładkę.
class SelfReviewsController < ApplicationController
  include DashboardShell

  def index
    remember_dashboard_tab("self")
  end
end
