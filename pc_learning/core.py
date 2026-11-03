"""Bounded serial framing, result validation, round tracking and local search."""
from dataclasses import dataclass
import re

from .knowledge import ARTICLES, QUESTIONS


@dataclass(frozen=True)
class Result:
    question: int
    selected: str
    answer: str
    correct: bool
    score: int


def parse_result(line: bytes) -> Result:
    match = re.fullmatch(rb"Q=([1-4]),SEL=([A-D]),ANS=([A-D]),OK=([01]),SCORE=(\d{3})\r?\n", line)
    if not match:
        raise ValueError("消息格式不完整或不符合答题协议")
    q, selected, answer, correct, score = match.groups()
    item = Result(int(q), selected.decode("ascii"), answer.decode("ascii"), correct == b"1", int(score))
    if item.answer != QUESTIONS[item.question]["answer"]:
        raise ValueError("板端正确答案与当前题库不一致")
    if item.correct != (item.selected == item.answer):
        raise ValueError("选项与判题结果不一致")
    award = 25 if item.correct else 0
    if item.score % 25 or not award <= item.score <= (item.question - 1) * 25 + award:
        raise ValueError("累计得分与题号、判题结果不一致")
    return item


class LineBuffer:
    def __init__(self):
        self.pending = bytearray()
        self.discarding = False

    def feed(self, data: bytes) -> list[bytes]:
        lines = []
        for byte in data:
            if self.discarding:
                if byte == 10:
                    self.discarding = False
                continue
            self.pending.append(byte)
            if byte == 10:
                lines.append(bytes(self.pending))
                self.pending.clear()
            elif len(self.pending) > 128:
                self.pending.clear()
                self.discarding = True
        return lines


class Round:
    def __init__(self):
        self.results: dict[int, Result] = {}

    def accept(self, item: Result) -> str:
        # The firmware has no session ID: every Q=1 is the start of a round.
        if item.question == 1:
            self.results = {1: item}
            return "new"
        if item.question in self.results:
            if self.results[item.question] == item:
                return "duplicate"
            raise ValueError("同一题出现不同结果，请从第 1 题重新开始")
        if self.results:
            previous = self.results[max(self.results)]
            if item.question <= previous.question:
                raise ValueError("题号回退，请从第 1 题重新开始")
            gap = item.question - previous.question - 1
            award = 25 if item.correct else 0
            if not award <= item.score - previous.score <= gap * 25 + award:
                raise ValueError("累计得分与上一条消息不一致")
        self.results[item.question] = item
        return "accepted"


def search(query: str) -> list[dict]:
    terms = query.casefold().split()
    ranked = []
    for index, article in enumerate(ARTICLES):
        title = article["title"].casefold()
        keywords = article["keywords"].casefold()
        text = title + " " + keywords + " " + article["body"].casefold()
        if all(term in text for term in terms):
            rank = sum(3 * (term in title) + (term in keywords) for term in terms)
            ranked.append((-rank, index, article))
    return [article for _, _, article in sorted(ranked)]
