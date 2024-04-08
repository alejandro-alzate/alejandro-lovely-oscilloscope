return function(moonshine)
  local shader = love.graphics.newShader[[
    extern number strength;
    extern number angle;
    extern vec2 direction;

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
      vec4 final_color = vec4(0.0);

      // Calculate offset based on direction and strength
      vec2 offset = direction * strength;

      // Accumulate samples along the offset direction
      final_color += Texel(tex, uv);
      final_color += Texel(tex, uv - 0.5 * offset);
      final_color += Texel(tex, uv - offset);
      final_color += Texel(tex, uv + 0.5 * offset);
      final_color += Texel(tex, uv + offset);

      // Average the accumulated samples
      final_color /= 5.0;

      return final_color;
    }
  ]]

  local setters = {}

  setters.strength = function(v)
    shader:send("strength", tonumber(v) or 1.0)
  end

  setters.angle = function(v)
    -- Convert angle in degrees to radians
    local radians = math.rad(tonumber(v) or 0)
    -- Calculate direction from angle
    local dir_x = math.cos(radians)
    local dir_y = math.sin(radians)
    shader:send("direction", {dir_x, dir_y})
  end

  local defaults = {
    strength = 1.0,
    angle = 0.0  -- Default direction is horizontal (0 degrees)
  }

  return moonshine.Effect{
    name = "motionblur",
    shader = shader,
    setters = setters,
    defaults = defaults
  }
end
