from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib

DEFAULT_ICLOUD_ROOT = Path(
    "~/Library/Mobile Documents/com~apple~CloudDocs/PaperManager"
).expanduser()

DEFAULT_LOCAL_ROOT = Path(
    "~/Library/Application Support/paper_manager"
).expanduser()

DEFAULT_CONFIG_PATH = Path.cwd() / "config.toml"

DEFAULT_CONFIG_TEMPLATE = """\
[storage]
icloud_root = "{icloud_root}"

[claude]
model = "claude-sonnet-4-6"

[embed]
model = "mxbai-embed-large"
"""


@dataclass
class Config:
    icloud_root: Path
    claude_model: str
    embed_model: str
    local_root: Path = DEFAULT_LOCAL_ROOT

    @property
    def library_dir(self) -> Path:
        return self.icloud_root / "library"

    @property
    def inbox_dir(self) -> Path:
        return self.icloud_root / "inbox"

    @property
    def user_dir(self) -> Path:
        return self.icloud_root / "user"

    @property
    def prefs_path(self) -> Path:
        return self.user_dir / "prefs.json"

    @property
    def history_path(self) -> Path:
        return self.user_dir / "history.jsonl"

    @property
    def sqlite_path(self) -> Path:
        return self.local_root / "library.sqlite"

    @property
    def chats_dir(self) -> Path:
        return self.local_root / "chats"


def load(path: Path | None = None) -> Config:
    cfg_path = path or DEFAULT_CONFIG_PATH
    if not cfg_path.exists():
        return Config(
            icloud_root=DEFAULT_ICLOUD_ROOT,
            claude_model="claude-sonnet-4-6",
            embed_model="mxbai-embed-large",
        )
    data = tomllib.loads(cfg_path.read_text())
    storage = data.get("storage", {})
    claude_cfg = data.get("claude", {})
    embed_cfg = data.get("embed", data.get("voyage", {}))
    icloud = Path(storage.get("icloud_root", str(DEFAULT_ICLOUD_ROOT))).expanduser()
    return Config(
        icloud_root=icloud,
        claude_model=claude_cfg.get("model", "claude-sonnet-4-6"),
        embed_model=embed_cfg.get("model", "mxbai-embed-large"),
    )


def write_default(path: Path | None = None, icloud_root: Path | None = None) -> Path:
    target = path or DEFAULT_CONFIG_PATH
    root = icloud_root or DEFAULT_ICLOUD_ROOT
    target.write_text(DEFAULT_CONFIG_TEMPLATE.format(icloud_root=str(root)))
    return target


def anthropic_key() -> str | None:
    return os.environ.get("ANTHROPIC_API_KEY")
