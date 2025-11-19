#include "shapecorners_shadows.glsl"

bool is_within(float point, float a, float b) { return (point >= min(a, b) && point <= max(a, b)); }
bool is_within(vec2 point, vec2 corner_a, vec2 corner_b)
{
    return is_within(point.x, corner_a.x, corner_b.x) && is_within(point.y, corner_a.y, corner_b.y);
}

/*
 *  \brief This function is used to choose the pixel color based on its distance to the center input.
 *  \param coord0: The XY point
 *  \param tex: The RGBA color of the pixel in XY
 *  \param start: The reference XY point to determine the center of the corner roundness.
 *  \param angle: The angle in radians to move away from the start point to determine the center of the corner roundness.
 *  \param is_corner: Boolean to know if its a corner or an edge
 *  \param coord_shadowColor: The RGBA color of the shadow of the pixel behind the window.
 *  \return The RGBA color to be used instead of tex input.
 */
vec4 shapeCorner(vec2 coord0, vec4 tex, vec2 start, float angle, vec4 coord_shadowColor)
{
    vec2  angle_vector         = vec2(cos(angle), sin(angle));
    float corner_length        = (abs(angle_vector.x) < 0.1 || abs(angle_vector.y) < 0.1) ? 1.0 : sqrt(2.0);
    vec2  roundness_center     = start + radius * angle_vector * corner_length;
    vec2  outlineStart         = start + outlineThickness * angle_vector * corner_length;
    vec2  secondOutlineStart   = start + (outlineThickness + secondOutlineThickness) * angle_vector * corner_length;
    vec2  outerOutlineEnd      = start - outerOutlineThickness * angle_vector * corner_length;
    float distance_from_center = distance(coord0, roundness_center);

    if (hasOuterOutline()) {
        vec4 outerOutlineOverlay = mix(coord_shadowColor, outerOutlineColor, outerOutlineColor.a);
        if (distance_from_center > radius + outerOutlineThickness - 0.5) {
            // antialiasing for the outer outline to shadow
            float antialiasing = clamp(distance_from_center - radius - outerOutlineThickness + 0.5, 0.0, 1.0);
            return mix(outerOutlineOverlay, coord_shadowColor, antialiasing);
        } else if (distance_from_center > radius - 0.5) {
            // antialiasing for the outer outline to the window edge
            float antialiasing = clamp(distance_from_center - radius + 0.5, 0.0, 1.0);
            if (hasPrimaryOutline()) {
                // if the primary outline is present
                vec4 outlineOverlay = vec4(mix(tex.rgb, outlineColor.rgb, outlineColor.a), 1.0);
                return mix(outlineOverlay, outerOutlineOverlay, antialiasing);
            } else if (hasSecondOutline()) {
                // if the second outline is present
                vec4 secondOutlineOverlay = vec4(mix(tex.rgb, secondOutlineColor.rgb, secondOutlineColor.a), 1.0);
                return mix(secondOutlineOverlay, outerOutlineOverlay, antialiasing);
            } else {
                // if the no other outline is not present
                return mix(tex, outerOutlineOverlay, antialiasing);
            }
        }
    } else {
        if (distance_from_center > radius - 0.5) {
            // antialiasing for the outer outline to the window edge
            float antialiasing = clamp(distance_from_center - radius + 0.5, 0.0, 1.0);
            if (hasPrimaryOutline()) {
                // if the primary outline is present
                vec4 outlineOverlay = vec4(mix(tex.rgb, outlineColor.rgb, outlineColor.a), 1.0);
                return mix(outlineOverlay, coord_shadowColor, antialiasing);
            } else if (hasSecondOutline()) {
                // if the second outline is present
                vec4 secondOutlineOverlay = vec4(mix(tex.rgb, secondOutlineColor.rgb, secondOutlineColor.a), 1.0);
                return mix(secondOutlineOverlay, coord_shadowColor, antialiasing);
            } else {
                // if the no other outline is not present
                return mix(tex, coord_shadowColor, antialiasing);
            }
        }
    }

    if (hasPrimaryOutline()) {
        vec4 outlineOverlay = vec4(mix(tex.rgb, outlineColor.rgb, outlineColor.a), 1.0);

        if (outlineThickness >= radius && is_within(coord0, outlineStart, start)) {
            // when the outline is bigger than the roundness radius
            // from the window to the outline is sharp
            // no antialiasing is needed because it is not round
            return outlineOverlay;
        } else if (distance_from_center > radius - outlineThickness - 0.5) {
            // from the window to the outline
            float antialiasing = clamp(distance_from_center - radius + outlineThickness + 0.5, 0.0, 1.0);
            if (hasSecondOutline()) {
                vec4 secondOutlineOverlay = vec4(mix(tex.rgb, secondOutlineColor.rgb, secondOutlineColor.a), 1.0);
                return mix(secondOutlineOverlay, outlineOverlay, antialiasing);
            } else {
                return mix(tex, outlineOverlay, antialiasing);
            }
        }
    }

    if (hasSecondOutline()) {
        vec4 secondOutlineOverlay = vec4(mix(tex.rgb, secondOutlineColor.rgb, secondOutlineColor.a), 1.0);

        if (outlineThickness + secondOutlineThickness >= radius && is_within(coord0, secondOutlineStart, start)) {
            // when the outline is bigger than the roundness radius
            // from the window to the outline is sharp
            // no antialiasing is needed because it is not round
            return secondOutlineOverlay;
        } else if (distance_from_center > radius - outlineThickness - secondOutlineThickness - 0.5) {
            // from the window to the outline
            float antialiasing =
                    clamp(distance_from_center - radius + outlineThickness + secondOutlineThickness + 0.5, 0.0, 1.0);
            return mix(tex, secondOutlineOverlay, antialiasing);
        }
    }

    // if other conditions don't apply, just don't draw an outline, from the window to the shadow
    float antialiasing = clamp(radius - distance_from_center + 0.5, 0.0, 1.0);
    return mix(coord_shadowColor, tex, antialiasing);
}

vec4 run_internal(vec2 texcoord0, vec4 tex)
{
    if (tex.a == 0.0) {
        return tex;
    }

    float r = max(radius, outlineThickness);

    /* Since `texcoord0` is ranging from {0.0, 0.0} to {1.0, 1.0} is not pixel intuitive,
     * I am changing the range to become from {0.0, 0.0} to {width, height}
     * in a way that {0,0} is the top-left of the window and not its shadow.
     * This means areas with negative numbers and areas beyond windowSize is considered part of the shadow. */
    vec2 coord0 = tex_to_pixel(texcoord0);

    vec4 coord_shadowColor = getShadow(coord0, r, tex);

    /*
        Split the window into these sections below. They will have a different center of circle for rounding.

        TL  T   T   TR
        L   x   x   R
        L   x   x   R
        BL  B   B   BR
    */
    if (coord0.y < r) {
        if (coord0.x < r) {
            return shapeCorner(coord0, tex, vec2(0.0, 0.0), radians(45.0), coord_shadowColor); // Section TL
        } else if (coord0.x > windowSize.x - r) {
            return shapeCorner(coord0, tex, vec2(windowSize.x, 0.0), radians(135.0), coord_shadowColor); // Section TR
        } else if (coord0.y < outlineThickness + secondOutlineThickness) {
            return shapeCorner(coord0, tex, vec2(coord0.x, 0.0), radians(90.0), coord_shadowColor); // Section T
        }
    } else if (coord0.y > windowSize.y - r) {
        if (coord0.x < r) {
            return shapeCorner(coord0, tex, vec2(0.0, windowSize.y), radians(315.0), coord_shadowColor); // Section BL
        } else if (coord0.x > windowSize.x - r) {
            return shapeCorner(coord0, tex, vec2(windowSize.x, windowSize.y), radians(225.0),
                               coord_shadowColor); // Section BR
        } else if (coord0.y > windowSize.y - outlineThickness - secondOutlineThickness) {
            return shapeCorner(coord0, tex, vec2(coord0.x, windowSize.y), radians(270.0),
                               coord_shadowColor); // Section B
        }
    } else {
        if (coord0.x < r) {
            return shapeCorner(coord0, tex, vec2(0.0, coord0.y), radians(0.0), coord_shadowColor); // Section L
        } else if (coord0.x > windowSize.x - r) {
            return shapeCorner(coord0, tex, vec2(windowSize.x, coord0.y), radians(180.0),
                               coord_shadowColor); // Section R
        }
        // For section x, the tex is not changing
    }
    return tex;
}

vec3 closestPointOnLine3D(vec3 _lineStart, vec3 _lineEnd, vec3 _pos, float _offset, out float o_lerp, out float o_lerpUnclamped)
{
	vec3 diff = _lineEnd - _lineStart;
	float lineLength = length(diff);
	//vec3 dir = diff / lineLength;
    vec3 dir = diff * (1.0 / lineLength);

	vec3 posDiff = _pos - _lineStart;
	float comp = dot(posDiff, dir);
	comp += _offset;
	o_lerpUnclamped = comp / lineLength;
	o_lerp = clamp(o_lerpUnclamped, 0.0f, 1.0f);
	vec3 linePos = (comp < 0.0f) ? _lineStart : ((comp > lineLength) ? _lineEnd : (_lineStart + (dir * comp)));

	return linePos;
}
vec3 closestPointOnLine3D(vec3 _lineStart, vec3 _lineEnd, vec3 _pos, out float o_lerp, out float o_lerpUnclamped)
{
	return closestPointOnLine3D(_lineStart, _lineEnd, _pos, 0.0f, o_lerp, o_lerpUnclamped);
}

float distToLine3D(vec3 _lineStart, vec3 _lineEnd, vec3 _pos, out float o_lerp, out float o_lerpUnclamped)
{
	vec3 linePos = closestPointOnLine3D(_lineStart, _lineEnd, _pos, o_lerp, o_lerpUnclamped);
	return length(_pos - linePos);
}

vec4 run(vec2 uv, vec4 tex)
{
    vec4 rounded = run_internal(uv, tex);

    /*
    float lum = dot(tex.rgb, vec3(0.333, 0.333, 0.333));
    float alpha = clamp(lum * 20.0, 0.0, 1.0);
    rounded.a *= alpha;
    */

    /*
    {
        vec3 chromaKey = vec3(0.0, 0.0, 0.0);
        float threshold = 0.5 / 255.0;
        vec3 backgroundColor = vec3(0.1, 0.1, 0.1);

        float colorDist = length(rounded.rgb - chromaKey);
        if (colorDist < threshold)
        {
            // This pixel is fully chromaKey
            rounded.rgb = backgroundColor;
            rounded.a = 0.0f;
        }
        else
        {
            vec2 pixelUVSize = vec2(1.0 / windowExpandedSize.x, 1.0 / windowExpandedSize.y);
            vec4 sampleNX = texture2D(sampler, uv + vec2(-pixelUVSize.x, 0.0));
            vec4 samplePX = texture2D(sampler, uv + vec2(pixelUVSize.x, 0.0));
            vec4 sampleNY = texture2D(sampler, uv + vec2(0.0, -pixelUVSize.y));
            vec4 samplePY = texture2D(sampler, uv + vec2(0.0, pixelUVSize.y));
            float colorDistNX = length(sampleNX.rgb - chromaKey);
            float colorDistPX = length(samplePX.rgb - chromaKey);
            float colorDistNY = length(sampleNY.rgb - chromaKey);
            float colorDistPY = length(samplePY.rgb - chromaKey);

            // Are there any full chromaKey pixels around this one?
            //if ((colorDistNX < threshold) || (colorDistPX < threshold) || (colorDistNY < threshold) || (colorDistPY < threshold))
            {
                vec3 furthestColor = rounded.rgb;
                float furthestColorDist = colorDist;
                if (colorDistNX > furthestColorDist)
                {
                    furthestColor = sampleNX.rgb;
                    furthestColorDist = colorDistNX;
                }
                if (colorDistPX > furthestColorDist)
                {
                    furthestColor = samplePX.rgb;
                    furthestColorDist = colorDistPX;
                }
                if (colorDistNY > furthestColorDist)
                {
                    furthestColor = sampleNY.rgb;
                    furthestColorDist = colorDistNY;
                }
                if (colorDistPY > furthestColorDist)
                {
                    furthestColor = samplePY.rgb;
                    furthestColorDist = colorDistPY;
                }

                float alpha = clamp(colorDist / furthestColorDist, 0.0, 1.0);
                rounded.rgb = mix(furthestColor, rounded.rgb, alpha);
                //float alpha = clamp(colorDist / 1.2, 0.0, 1.0);
                //rounded.rgb *= 1.0 / max(alpha, 0.01);

                rounded.a *= alpha;
            }
        }
    }
    */

    //
    {
        vec3 windowBackgroundDark = vec3(20.0 / 255.0, 22.0 / 255.0, 24.0 / 255.0);         // Darkest part of window
        vec3 windowBackgroundBright = vec3(32.0 / 255.0, 35.0 / 255.0, 38.0 / 255.0);       // Used for buttons and alternate window parts
        vec3 windowBackgroundBrightest = vec3(41.0 / 255.0, 44.0 / 255.0, 48.0 / 255.0);    // Used for active header

        vec3 chromaKey = vec3(0.0);//windowBackgroundDark;
        vec3 chromaKeyMax = windowBackgroundBrightest;
        // Average of windowBackgroundDark and windowBackgroundBright
        //vec3 chromaKey = vec3(26.0 / 255.0, 28.5 / 255.0, 31.0 / 255.0);

        //float chromaKeyRadius = 10.0 / 255.0;
        //float falloff = 0.2;
        //float chromaKeyRadius = 2.0 / 255.0;
        //float falloff = 0.05;//0.2;
        float chromaKeyRadius = 0.0 / 255.0;
        float falloff = 0.6;

        float alphaMin = 0.6;
        float alphaMax = 1.0;

        //vec3 colorDelta = tex.rgb - chromaKey;
        //float colorDist = length(colorDelta);
        //colorDelta = tex.rgb - chromaKeyMax;
        //colorDist = min(colorDist, length(colorDelta));
        //
        float lerp;
        float lerpUnclamped;
        float colorDist = distToLine3D(chromaKey, chromaKeyMax, tex.rgb, lerp, lerpUnclamped);

        colorDist = max(0.0, colorDist - chromaKeyRadius);

        float alpha = clamp(colorDist / falloff, 0.0, 1.0);
        //alpha = smoothstep(0.0, 1.0, alpha);

        alpha = mix(alphaMin, alphaMax, alpha);
        // Premultiplied alpha, so multiply all components.
        rounded *= alpha;

        // Debug display alpha
        //rounded.rgb = vec3(alpha);
        //rounded.a = 1.0f;
    }
    //

    // TODO: Version of above but sample alpha for kernel around current pixel. Then do screen of current pixel value with blurred value.
    // Screen being 1.0 - ((1.0 - a) * (1.0 - b)).
    // Idea is to softly expand out higher alpha value over lower alpha values.

    /*
    {
        //vec3 chromaKey = vec3(0.0, 0.0, 0.0);
        //vec3 chromaKey = vec3(20.0 / 255.0, 22.0 / 255.0, 24.0 / 255.0);
        vec3 chromaKey = vec3(41.0 / 255.0, 44.0 / 255.0, 48.0 / 255.0);

        // Settings
        // Solid extra pixel around foreground
        //int kernelHalfSize = 4;
        //float solidDist = 1.0;
        //float curvePower = 2.0;
        //float alphaMin = 0.65;
        //float alphaMax = 1.0;
        // Solid extra pixel with minimal fade
        //int kernelHalfSize = 2;
        //float solidDist = 1.0;
        //float curvePower = 2.0;
        //float alphaMin = 0.65;
        //float alphaMax = 1.0;
        // Minimal border. Looks good but slight aliasing as there's no solid area.
        int kernelHalfSize = 4;
        float solidDist = 0.0;
        float curvePower = 4.0;
        float alphaMin = 0.65;
        float alphaMax = 1.0;
        // Solid area behind foreground
        //int kernelHalfSize = 16;
        //float solidDist = 12.0;
        //float curvePower = 2.0;
        //float alphaMin = 0.65;
        //float alphaMax = 1.0;
        //
        //int kernelHalfSize = 16;
        //float solidDist = 1.0;
        //float curvePower = 4.0;
        //float alphaMin = 0.65;
        //float alphaMax = 1.0;

        float thresholdSqr = (0.5 / 255.0) * (0.5 / 255.0);

        vec2 pixelUVSize = vec2(1.0 / windowExpandedSize.x, 1.0 / windowExpandedSize.y);

        float minDistSqr = 999999.0;
        for (int y = -kernelHalfSize; y <= kernelHalfSize; y++)
        {
            for (int x = -kernelHalfSize; x <= kernelHalfSize; x++)
            {
                //int x = 0;
                //int y = 0;

                vec4 sampleColor = texture2D(sampler, uv + vec2(float(x) * pixelUVSize.x, float(y) * pixelUVSize.y));
                vec3 colorDelta = sampleColor.rgb - chromaKey;
                float colorDistSqr = dot(colorDelta, colorDelta);
                if (colorDistSqr > thresholdSqr)
                {
                    // Not background
                    vec2 delta = vec2(float(x), float(y));
                    float distSqr = dot(delta, delta);
                    minDistSqr = min(minDistSqr, distSqr);
                }
            }
        }

        float minDist = sqrt(minDistSqr);

        minDist = max(0.0, minDist - solidDist);

        float alpha = clamp(1.0 - (minDist / (float(kernelHalfSize + 1) - solidDist)), 0.0, 1.0);
        alpha = pow(alpha, curvePower);
        alpha = mix(alphaMin, alphaMax, alpha);

        // Premultiplied alpha, so multiply all components.
        rounded *= alpha;
    }
    */

    return rounded;
}
