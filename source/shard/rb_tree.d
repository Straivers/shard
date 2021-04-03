module shard.rb_tree;

import shard.memory : Allocator;
import shard.pad : pad_bytes;

/**
Implements a left-leaning red-black tree. Each key may be associated with
several values, and removal by key will only remove one value.
*/
struct RbTree(Key, Value) {
    static assert(0, "Work in progress, do not use.");

    bool contains(Key key) {
        return _find_node(key) !is null;
    }

    Value search(Key key) {
        if (auto n = _find_node(key))
            return n.value;
        assert(0, "Value not found");
    }

    void insert(Key key, Value value) {
        static _insert(_Node* n, Key k, Value v) {
            if (!n) return new _Node(k, v);

            if (_is_red(n.left) && _is_red(n.right)) n.flip_colors();

            if (k == n.key)     assert(0, "Duplicate keys");
            else if (k < n.key) n.left = _insert(n.left, k, v);
            else                n.right = _insert(n.right, k, v);

            return _fixup(n);
        }

        _root = _insert(_root, key, value);
        _root.color = black;
    }

    void remove(Key key) {
        static _Node* _remove(_Node* n, Key k) {
            if (k < n.key) {
                if (!_is_red(n.left) && !_is_red(n.left.left))
                    n = _move_red_left(n);
                n.left = _remove(n.left, k);
            }
            else {
                if (_is_red(n.left))
                    n = _rotate_right(n);
                if (k == n.key && n.right is null)
                    return null;
                if (!_is_red(n.right) && !_is_red(n.right.left))
                    n = _move_red_right(n);
                if (k == n.key) {
                    _Node* min;
                    _remove_min(n.right, min);
                    *n = *min;
                }
                else n.right = _remove(n.right, k);
            }

            return _fixup(n);
        }

        _root = _remove(_root, key);
        _root.color = black;
    }

private:
    enum red = false;
    enum black = true;

    struct _Node {
        Key key;
        Value value;

        bool color = red;
        _Node* left, right;

        void flip_colors() {
            color = !color;
            left.color = !left.color;
            right.color = !right.color;
        }
    }

    static _Node* _rotate_left(_Node* node) {
        auto x = node.right;
        node.right = x.left;
        x.left = node;
        x.color = node.color;
        node.color = red;
        return x;
    }

    static _Node* _rotate_right(_Node* node) {
        auto x = node.left;
        node.left = x.right;
        x.right = node;
        x.color = node.color;
        node.color = red;
        return x;
    }

    static bool _is_red(_Node* node) {
        return node !is null && node.color == red;
    }

    static _Node* _fixup(_Node* node) {
        if (_is_red(node.right) && !_is_red(node.left))     node = _rotate_left(node);
        if (_is_red(node.left) && _is_red(node.left.left))  node = _rotate_right(node);
        return node;
    }

    static _Node* _move_red_left(_Node* node) {
        node.flip_colors();
        if (_is_red(node.right.left)) {
            node.right = _rotate_right(node.right);
            node = _rotate_left(node);
            node.flip_colors();
        }
        return node;
    }

    static _Node* _move_red_right(_Node* node) {
        node.flip_colors();
        if (_is_red(node.left.left)) {
            node = _rotate_right(node);
            node.flip_colors();
        }
        return node;
    }

    static _Node* _remove_min(_Node* node, ref _Node* min) {
        if (!node.left) {
            min = node;
            return null;
        }

        if (!_is_red(node.left) && !_is_red(node.left.left))
            node = _move_red_left(node);
        
        node.left = _remove_min(node.left, min);
        return _fixup(node);
    }

    _Node* _find_node(Key key) {
        for (auto x = _root; x !is null;) {
            if (x.key == key)       return x;
            else if (key < x.key)   x = x.left;
            else if (key > x.key)   x = x.right;
        }
        return null;
    }

    _Node* _root;
}

unittest {
    RbTree!(uint, uint) tree;

    tree.insert(1, 100);
    tree.insert(2, 200);
    tree.insert(3, 300);
    tree.insert(4, 400);

    assert(!tree.contains(0));
    assert(!tree.contains(100));

    assert(tree.contains(4));
    assert(tree.contains(3));
    assert(tree.contains(2));
    assert(tree.contains(1));

    assert(tree.search(1) == 100);
    assert(tree.search(3) == 300);
    assert(tree.search(2) == 200);
    assert(tree.search(4) == 400);

    tree.insert(5, 400);
    tree.insert(6, 400);
    tree.insert(7, 400);
    tree.insert(8, 400);
    tree.insert(9, 400);
    tree.insert(10, 400);
    tree.insert(11, 400);
    tree.insert(12, 400);
    tree.insert(13, 400);

    tree.remove(1);
    assert(!tree.contains(1));
}
