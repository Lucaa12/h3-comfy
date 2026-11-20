"""Open Engine Tools: three small helper boxes used by Open_Echo_v2 / Open_Motion_v2.

  OpenCrossfadeJoin  join two video parts and blend the frames the two parts share
  OpenMaskGrow       make the person's coloured mask a few pixels bigger (hair edges)
  OpenBlendFrames    mix a processed video with the original (strength 0..1), the
                     processed video is only rendered when the strength is above 0

Plain PyTorch only, no extra packages. Licence: MIT.
"""
import torch
import torch.nn.functional as F

try:
    import comfy.model_management as _mm
    _DEV = _mm.get_torch_device()
except Exception:  # running outside ComfyUI (tests)
    _DEV = torch.device("cpu")

CHUNK = 16  # frames handled at once on the graphics card


class OpenCrossfadeJoin:
    """previous + new -> one video.

    The extra frames the engine makes at the start of every part (`overlap`, 5 by default) show the same
    moment as the last frames of the previous part. With crossfade on, those frames are blended
    (previous -> new) instead of being cut, so the join has no pop.
    With crossfade off the result is the same as the old join: previous + new without its first
    `overlap` frames.
    """

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "previous": ("IMAGE",),
            "new": ("IMAGE",),
            "overlap": ("INT", {"default": 5, "min": 1, "max": 32}),
            "crossfade": ("BOOLEAN", {"default": True}),
        }}

    RETURN_TYPES = ("IMAGE",)
    FUNCTION = "join"
    CATEGORY = "Open Engine"

    def join(self, previous, new, overlap, crossfade):
        k = int(min(overlap, new.shape[0]))
        if not crossfade or k < 1 or previous.shape[0] < k:
            return (torch.cat([previous, new[k:]], dim=0),)
        w = torch.arange(1, k + 1, dtype=previous.dtype, device=previous.device) / (k + 1)
        w = w.view(k, 1, 1, 1)
        mix = previous[-k:] * (1.0 - w) + new[:k].to(previous.dtype) * w
        return (torch.cat([previous[:-k], mix, new[k:].to(previous.dtype)], dim=0),)


class OpenMaskGrow:
    """Grow the coloured person region of a SCAIL-2 mask by `pixels`.

    Only the background next to the person is repainted, with the person's own colour, so the
    colours of the masks are never changed and nothing is blurred.
    white_background: True for Replacement Mode masks (white background), False for black.
    """

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "masks": ("IMAGE",),
            "pixels": ("INT", {"default": 4, "min": 0, "max": 64}),
            "white_background": ("BOOLEAN", {"default": False}),
        }}

    RETURN_TYPES = ("IMAGE",)
    FUNCTION = "grow"
    CATEGORY = "Open Engine"

    def grow(self, masks, pixels, white_background):
        if pixels <= 0:
            return (masks,)
        out = torch.empty_like(masks)
        k = 2 * int(pixels) + 1
        for i in range(0, masks.shape[0], CHUNK):
            x = masks[i:i + CHUNK].to(_DEV).float()
            if white_background:
                x = 1.0 - x
            person = (x[..., :3].amax(dim=-1, keepdim=True) > 0.05)
            xp = x.permute(0, 3, 1, 2)
            big = F.max_pool2d(xp, kernel_size=k, stride=1, padding=int(pixels)).permute(0, 2, 3, 1)
            y = torch.where(person, x, big)
            if white_background:
                y = 1.0 - y
            out[i:i + CHUNK] = y.to(out.dtype).to(out.device)
        return (out,)


class OpenBlendFrames:
    """result = original * (1 - strength) + processed * strength.

    `processed` is lazy: at strength 0 it is never rendered, so the pass costs nothing when off.
    """

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "original": ("IMAGE",),
            "strength": ("FLOAT", {"default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05}),
        }, "optional": {
            "processed": ("IMAGE", {"lazy": True}),
        }}

    RETURN_TYPES = ("IMAGE",)
    FUNCTION = "blend"
    CATEGORY = "Open Engine"

    def check_lazy_status(self, original, strength, processed=None):
        if strength > 0 and processed is None:
            return ["processed"]
        return []

    def blend(self, original, strength, processed=None):
        if strength <= 0 or processed is None:
            return (original,)
        if strength >= 1:
            return (processed,)
        out = torch.empty_like(original)
        for i in range(0, original.shape[0], CHUNK):
            a = original[i:i + CHUNK].to(_DEV).float()
            b = processed[i:i + CHUNK].to(_DEV).float()
            if b.shape != a.shape:  # the pass must keep the size; resize only as a safety net
                b = F.interpolate(b.permute(0, 3, 1, 2), size=a.shape[1:3], mode="bilinear",
                                  align_corners=False).permute(0, 2, 3, 1)
            out[i:i + CHUNK] = torch.lerp(a, b, float(strength)).clamp_(0, 1).to(out.dtype).to(out.device)
        return (out,)


NODE_CLASS_MAPPINGS = {
    "OpenCrossfadeJoin": OpenCrossfadeJoin,
    "OpenMaskGrow": OpenMaskGrow,
    "OpenBlendFrames": OpenBlendFrames,
}
NODE_DISPLAY_NAME_MAPPINGS = {
    "OpenCrossfadeJoin": "Open · Crossfade join",
    "OpenMaskGrow": "Open · Grow mask",
    "OpenBlendFrames": "Open · Blend frames",
}
