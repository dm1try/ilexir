defmodule Ilexir.Linter.Compiler do
  alias Ilexir.QuickFix.Item
  alias Ilexir.StandardErrorStub

  def run(file, content) do
    old_ignore_module_opt = Code.compiler_options[:ignore_module_conflict]
    if !old_ignore_module_opt, do: Code.compiler_options(ignore_module_conflict: true)

    res = StandardErrorStub.with_stab_standard_error fn->
      Ilexir.Compiler.compile_string(content, file)
    end

    if !old_ignore_module_opt, do: Code.compiler_options(ignore_module_conflict: false)

    case res do
      {:error, error} ->
        [compiler_error_to_item(error, file)]
      _ ->
        compiler_warnings_to_items(StandardErrorStub.warnings(), file)
    end
  end

  def compiler_warnings_to_items(warnings, file) do
    Enum.map(warnings, fn(warning)->
      compiler_warning_to_item(warning,file)
    end)
  end

  def compiler_warning_to_item(%{text: text, line: line} = _warning, file) do
    %Item{file: file, text: text, type: :warning, location: %Item.Location{line: line}}
  end

  def compiler_warning_to_item(warning, file) do
    %Item{file: file, text: "#{inspect warning}", type: :warning, location: %Item.Location{line: 1}}
  end

  def compiler_error_to_item(%{description: text, line: line, file: _file}, file) do
    %Item{file: file, text: text, type: :error, location: %Item.Location{line: line}}
  end

  def compiler_error_to_item(%UndefinedFunctionError{function: function, arity: arity, module: module}, file) do
    %Item{file: file, text: "#{inspect module}.#{function}/#{arity} is undefined", type: :error, location: %Item.Location{line: 1}}
  end

  def compiler_error_to_item(error, file) do
    %Item{file: file, text: "#{inspect error}", type: :error, location: %Item.Location{line: 1}}
  end
end
