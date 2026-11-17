using System.Collections.Generic;

namespace FirstPersonSokoban.Core
{
    public sealed class UndoManager
    {
        private readonly Stack<BoardSnapshot> history = new Stack<BoardSnapshot>();
        public int Count => history.Count;
        public void Clear() => history.Clear();
        public void Record(BoardSnapshot snapshot) => history.Push(snapshot);
        public bool CanUndo => history.Count > 0;
        public BoardSnapshot Pop() => history.Pop();
    }
}
