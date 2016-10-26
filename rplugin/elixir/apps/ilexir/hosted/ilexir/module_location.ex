defmodule Ilexir.ModuleLocation do
  @moduledoc """
  The code here smells not so good :)
  """
  def to_location_tree(ast) do
    root_node = {{nil, [0, nil],[]}, [{0,0}], []}
    {_, {tree, _, _}} = Macro.traverse(ast, root_node, &pre_traverse_callback/2, &post_traverse_callback/2)

    tree
  end

  defp pre_traverse_callback({:defmodule, _, [{:__aliases__, args, aliases} = module_alias|_]} = n, {tree, _, []}) do
    child_mod_name = Module.concat(aliases)
    line = Keyword.get(args, :line)
    new_node = {child_mod_name, [line, nil], []}

    tree = put_elem(tree, 2, [new_node])
    {n, {tree, [{0,0}], [module_alias]}}
  end

  defp pre_traverse_callback({:defmodule, _args, [{:__aliases__, args, aliases} = module_alias|_rest]} = n, {tree, current_path, stack}) do
    access_path = access_path(current_path)

    parent_mod_name = get_in(tree, access_path ++ [Access.elem(0)])
    child_mod_name = Module.concat([parent_mod_name] ++ aliases)
    line = Keyword.get(args, :line)
    new_scope = {child_mod_name, [line, nil], []}

    children_access_path = access_path ++ [Access.elem(2)]
    children = get_in(tree, children_access_path)
    new_tree = put_in(tree, children_access_path, children ++ [new_scope])
    [{_, last_node_children_count} | _] = current_path
    new_path = [{last_node_children_count, 0} | current_path]

    {n, {new_tree, new_path, [module_alias|stack]}}
  end

  defp pre_traverse_callback(n, acc), do: {n, acc}

  defp post_traverse_callback({:defmodule, _, [module_alias|_rest]} = n,
   {tree, current_path, [last_token|rest_tokens]})
  when module_alias == last_token and length(current_path) <= 1 do
    {n, {tree, [], rest_tokens}}
  end

  defp post_traverse_callback({:defmodule, args, [module_alias|_rest]} = n,
   {tree, current_path, [last_token|rest_tokens]})
  when module_alias == last_token do
    [{current_index, _} | parent_path] = current_path

    new_tree = if current_index > 0 do
      parrent_access_path = access_path(parent_path)
      line = Keyword.get(args, :line)
      put_in(tree, parrent_access_path ++ [Access.elem(2), Access.at(current_index-1), Access.elem(1), Access.at(1)], line)
    else
      tree
    end

    [_, {last_node_index, last_node_children_count} | rest_path] = current_path
    new_path = [{last_node_index, last_node_children_count + 1} | rest_path]

    {n, {new_tree, new_path, rest_tokens}}
  end

  defp post_traverse_callback(n, acc), do: {n, acc}

  defp access_path(current_path) do
    current_path |> Enum.reverse |> Enum.flat_map(fn({index,_})->
      [Access.elem(2), Access.at(index)]
    end)
  end

  def find_module(nil, _line_number), do: nil
  def find_module({module, [start_line, end_line], []} = _tree, line) do
    if start_line <= line && end_line > line, do: module
  end

  def find_module({module, [start_line, nil], children} = _tree, line) do
    if start_line <= line do
      Enum.find_value(children, &find_module(&1, line)) || module
    end
  end

  def find_module({module, [start_line, end_line], children} = _tree, line) do
    if start_line <= line && end_line > line do
      Enum.find_value(children, &find_module(&1, line)) || module
    end
  end
end
