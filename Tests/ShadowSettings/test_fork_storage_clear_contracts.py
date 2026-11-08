"""Source contracts: fork storage clears reach every stored message (2.2.5).

The counts and both clears used to read only the preferences index, which
misses messages it never captured (and refs older builds dropped), so
«Удалить все удалённые» and «Удалить сохранённые правки» removed nothing in
groups. They now rescan the stored messages first.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path: str) -> str:
    return (SUB / path).read_text(encoding="utf-8")


class ForkStorageClearContracts(unittest.TestCase):
    def test_rescan_reads_stored_messages(self) -> None:
        store = read("TelegramCore/Sources/AyuGram/AyuForkStore.swift")
        rescan = store.split("public func ayuForkStoreRescan(transaction: Transaction)", 1)[1]
        rescan = rescan[:rescan.index("\npublic func ")]
        for needle in (
            "transaction.chatListGetAllPeerIds()",
            "transaction.scanMessageAttributes(",
            "Namespaces.Message.SecretIncoming",
            "DeletedMessageAttribute",
            "SavedMessageEditsAttribute",
        ):
            self.assertIn(needle, rescan)

    def test_clears_and_counts_use_rescan(self) -> None:
        store = read("TelegramCore/Sources/AyuGram/AyuForkStore.swift")
        for function in ("ayuForkStoreCounts", "ayuForkStoreClearKeptDeleted", "ayuForkStoreClearEditHistory"):
            body = store.split(f"public func {function}(", 1)[1]
            body = body[:body.index("\npublic func ")] if "\npublic func " in body else body
            self.assertIn("ayuForkStoreRescan(transaction: transaction)", body, function)

    def test_controller_repairs_before_listing(self) -> None:
        controller = read("SettingsUI/Sources/AyuForkStorageController.swift")
        rescan = controller.index("ayuForkStoreRescan(transaction: transaction)")
        self.assertLess(rescan, controller.index("let store = ayuForkStore(transaction: transaction)", rescan))


if __name__ == "__main__":
    unittest.main()
