defmodule Jake do
  alias Jake.MapUtil
  alias Jake.Context

  @types [
    "array",
    "boolean",
    "integer",
    "null",
    "number",
    "object",
    "string"
  ]

  def generator(schema) do
    StreamData.sized(fn size ->
      %Context{root: schema, child: schema, size: size} |> gen_lazy()
    end)
  end

  def gen_lazy(context) do
    StreamData.bind(
      get_lazy_streamkey(context),
      fn {child, size} ->
        gen(child, %{context | child: child, size: size}) |> StreamData.resize(size)
      end
    )
  end

  def get_lazy_streamkey(context) do
    {child, ref} =
      get_in(context.child, ["$ref"]) |> Jake.Ref.expand_ref(context.child, context.root)

    if ref do
      StreamData.constant({child, trunc(context.size / 2)})
    else
      StreamData.constant({child, context.size})
    end
  end

  def gen(%{"enum" => enum} = spec, _context) when is_list(enum) do
    StreamData.member_of(enum)
    |> StreamData.filter(fn x -> ExJsonSchema.Validator.valid?(spec, x) end)
  end

  def gen(%{"anyOf" => options} = spec, context) when is_list(options) do
    Enum.map(options, fn option ->
      child = Map.merge(Map.drop(spec, ["anyOf"]), option)
      %{context | child: child} |> gen_lazy()
    end)
    |> StreamData.one_of()
  end

  def gen(%{"allOf" => options} = spec, context) when is_list(options) do
    properties =
      options
      |> Enum.reduce(%{}, fn x, acc -> MapUtil.deep_merge(x, acc) end)

    child =
      spec
      |> Map.drop(["allOf"])
      |> MapUtil.deep_merge(properties)

    %{context | child: child} |> gen_lazy()
  end

  def gen(%{"type" => type} = spec, context) when is_binary(type) do
    module = String.to_existing_atom("Elixir.Jake.#{String.capitalize(type)}")
    apply(module, :gen, [spec, context])
  end

  def gen(%{"type" => types} = spec, context) when is_list(types) do
    Enum.map(types, fn type ->
      child = %{spec | "type" => type}

      %{context | child: child}
      |> gen_lazy()
    end)
    |> StreamData.one_of()
  end

  # type not present
  def gen(spec, context) do
    StreamData.member_of(@types)
    |> StreamData.bind(fn type ->
      child = Map.put(spec, "type", type)
      size = trunc(context.size / 2)
      %{context | child: child, size: size} |> gen_lazy()
    end)
  end
end
