defmodule Ilexir.ModuleLocationSpec do
  use ESpec

  alias Ilexir.ModuleLocation

  let :some_code_ast do
    """
    defmodule RootModule do
      alias File, as: F

      def func do
        F.read "file"
      end

      defmodule Inner do
        def some_func, do: 1
      end

      defmodule Inner2 do
        def yo do
        end
      end

      defmodule Inner3 do
        def yo do
        end

        defmodule InnerInInner do
          def some_method do
            "1"
          end
        end
      end

      defmodule Inner4 do
        def yo do
          a = 1
          b = 2

          a + b
        end
      end
    end
    """ |> Code.string_to_quoted!
  end

  it "builds location tree based on AST and searches for modules by providing line number" do
    tree =  ModuleLocation.to_location_tree(some_code_ast())

    expect(ModuleLocation.find_module(tree, 1)).to eq(RootModule)
    expect(ModuleLocation.find_module(tree, 7)).to eq(RootModule)

    expect(ModuleLocation.find_module(tree, 8)).to eq(RootModule.Inner)
    expect(ModuleLocation.find_module(tree, 9)).to eq(RootModule.Inner)

    expect(ModuleLocation.find_module(tree, 23)).to eq(RootModule.Inner3.InnerInInner)

    expect(ModuleLocation.find_module(tree, 33)).to eq(RootModule.Inner4)
  end
end
