module shard.utils.intrusive_list;


mixin template intrusive_list(T) {
    T* prev, next;

    struct ListHead {
        T* first, last;

        bool is_empty() {
            return first is null;
        }

        void push_front(T* new_node) {
            if (is_empty) {
                first = last = new_node;
            }
            else {
                assert(last);
                new_node.next = first;
                first.prev = new_node;
                first = new_node;
            }
        }

        void push_back(T* new_node) {
            if (is_empty) {
                first = last = new_node;
            }
            else {
                assert(first);
                new_node.prev = last;
                last.next = new_node;
                last = new_node;
            }
        }

        T* pop_front() {
            if (is_empty)
                return null;

            auto node = first;

            first = node.next;
            if (first) first.prev = null;
            else last = null;

            node.prev = node.next = null;
            return node;
        }

        T* pop_back() {
            if (is_empty)
                return null;

            auto node = last;
            assert(node.next is null);

            last = node.prev;
            if (last !is null) last.next = null;
            else first = null;
            node.prev = null;
            return node;
        }

        void remove(T* node) {
            if (node is first)
                pop_front();
            else if (node is last)
                pop_back();
            else {
                auto prev = node.prev;
                auto next = node.next;
                prev.next = next;
                next.prev = prev;
                node.next = node.prev = null;
            }
        }

        T* opIndex(size_t index) {
            for (auto node = first; node !is null; node = node.next) {
                if (index == 0)
                    return node;

                index--;
            }

            return null;
        }

        pragma(inline, true)
        auto opIndex() {
            static struct Range {
                ListHead* head;
                T* current;

                bool empty() {
                    return current is null;
                }

                pragma(inline, true)
                T* front() {
                    return current;
                }

                pragma(inline, true)
                void popFront() {
                    current = current.next;
                }
            }

            return Range(&this, first);
        }
    }
}

unittest {
    struct Foo {
        int value;

        mixin intrusive_list!Foo;
    }

    Foo.ListHead list;

    assert(list.is_empty);
    list.push_front(new Foo(100));
    assert(!list.is_empty);
    assert(list[0].value == 100);

    list.push_back(new Foo(200));
    assert(list[0].value == 100);
    assert(list[1].value == 200);

    assert(list.pop_back().value == 200);
    assert(list.pop_back().value == 100);
    assert(list.is_empty());

    foreach (i; 0 .. 100)
        list.push_back(new Foo(i));
    
    foreach (i; 0 .. 100)
        assert(list.pop_front().value == i);
    assert(list.is_empty());
}
