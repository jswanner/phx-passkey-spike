defmodule HandrollWeb.PageController do
  use HandrollWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
